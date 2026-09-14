import Clocks
import Foundation
import LanguageServerProtocol
import Testing
@testable import BylawsLSP

@Suite("LSP editor diagnostics")
struct EditorDiagnosticsTests {
  @Test(
    "Document open updates report from editor text",
    arguments: [false, true]
  )
  func openDocument(supportsPull: Bool) async throws {
    let project = try DiagnosticTestProject(source: "final class Good {}")
    let state = await makeServingState(
      project: project,
      supportsPull: supportsPull
    )
    let uri = DocumentURI(project.source)
    await state.initialized()
    #expect(try await diagnosticItems(from: state, for: uri).isEmpty)

    await state.didOpen(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: uri,
          language: .swift,
          version: 1,
          text: "class Bad {}"
        )
      )
    )

    let items = try await diagnosticItems(from: state, for: uri)
    #expect(items.count == 1)
    #expect(items.first?.code == .string("final-classes"))
  }

  @Test(
    "Pull request starts pending refresh without delay",
    .timeLimit(.minutes(3))
  )
  func pullDuringDelay() async throws {
    let project = try DiagnosticTestProject(source: "final class Good {}")
    let clock = TestClock()
    let start = clock.now
    let state = BylawsLanguageServerState(
      clock: clock,
      client: TestConnection()
    )
    var request = initializeRequest(root: project.root, supportsPull: true)
    request.initializationOptions = .dictionary([
      "refreshDelayMilliseconds": .int(100),
    ])
    _ = await state.initialize(request)
    let uri = DocumentURI(project.source)
    #expect(try await diagnosticItems(from: state, for: uri).isEmpty)

    await state.didChange(changeNotification(of: uri, to: "class Bad {}"))
    let items = try await diagnosticItems(from: state, for: uri)

    #expect(items.count == 1)
    #expect(items.first?.code == .string("final-classes"))
    #expect(clock.now == start)
    await state.shutdown()
  }

  @Test("Push diagnostics use unsaved text")
  func pushAfterEdit() async throws {
    let project = try DiagnosticTestProject(source: "final class Good {}")
    let connection = TestConnection()
    let state = await makeServingState(
      client: connection,
      project: project,
      supportsPull: false
    )
    await state.initialized()
    #expect(connection.publishedDiagnostics.last?.diagnostics.isEmpty != false)

    let uri = DocumentURI(project.source)
    await state.didChange(changeNotification(of: uri, to: "class Bad {}"))
    await state.waitForPendingRefresh()

    let published = try #require(
      connection.publishedDiagnostics.last { $0.uri == uri }
    )
    #expect(published.diagnostics.count == 1)
    #expect(
      published.diagnostics.first?.message
        .contains("Bad violates 'Classes are final'") == true
    )
  }

  @Test("Save restores diagnostics from disk")
  func saveDocument() async throws {
    let project = try DiagnosticTestProject(source: "final class Good {}")
    let connection = TestConnection()
    let state = await makeServingState(
      client: connection,
      project: project,
      supportsPull: false
    )
    await state.initialized()
    let uri = DocumentURI(project.source)
    await state.didChange(changeNotification(of: uri, to: "class Bad {}"))
    await state.waitForPendingRefresh()
    #expect(
      connection.publishedDiagnostics.last { $0.uri == uri }?
        .diagnostics.count == 1
    )

    await state.didSave(saveNotification(for: uri))

    let published = try #require(
      connection.publishedDiagnostics.last { $0.uri == uri }
    )
    #expect(published.diagnostics.isEmpty)
  }

  @Test("Pull diagnostics use unsaved text")
  func pullAfterEdit() async throws {
    let project = try DiagnosticTestProject(source: "final class Good {}")
    let state = await makeServingState(project: project, supportsPull: true)
    let uri = DocumentURI(project.source)

    await state.didChange(changeNotification(of: uri, to: "class Bad {}"))
    await state.waitForPendingRefresh()

    let items = try await diagnosticItems(from: state, for: uri)
    #expect(items.count == 1)
    #expect(items.first?.code == .string("final-classes"))
  }

  @Test("Incomplete editor text keeps previous diagnostics", arguments: [
    "Rule(\"editor-check\") { app.classes.violations(of: .isFinal) }",
    "Rule(\"editor-check\") { app.checkLayering(layers) }",
    """
    func checkClasses(_ codebase: Codebase) async -> Violations<Class> {
      try await codebase.classes.violations(of: .isFinal)
    }
    let rules: [Rule] = [Rule("editor-check") { try await checkClasses(app) }]
    """,
  ])
  func incompleteSource(rule: String) async throws {
    let project = try DiagnosticTestProject(
      source: "final class Good {}",
      rules: """
      let app = Codebase(including: ["Sources/**"])
      let layers = Layering(
        Layer("App", files: ["Sources/App/**"]),
        Layer("UI", files: ["Sources/UI/**"])
      )
      \(rule)
      """,
      files: ["Sources/UI/UI.swift": "struct UI {}"]
    )
    let state = await makeServingState(project: project, supportsPull: true)
    let uri = DocumentURI(project.source)
    await state.didChange(changeNotification(
      of: uri,
      to: "import UI\nclass Bad {}"
    ))
    await state.waitForPendingRefresh()
    #expect(try await diagnosticItems(from: state, for: uri).count == 1)

    await state.didChange(changeNotification(
      of: uri,
      to: "import UI\nclass Bad {}\nclass B"
    ))
    await state.waitForPendingRefresh()

    let items = try await diagnosticItems(from: state, for: uri)
    #expect(items.count == 1)
    #expect(items.first?.code == .string("editor-check"))
    let rules = try await diagnosticItems(
      from: state,
      for: DocumentURI(project.rules)
    )
    #expect(rules.isEmpty)
  }

  @Test("Saved syntax error reports source diagnostic")
  func savedSyntaxError() async throws {
    let project = try DiagnosticTestProject(source: "final class Good {}")
    let state = await makeServingState(project: project, supportsPull: true)
    let uri = DocumentURI(project.source)
    await state.didChange(changeNotification(of: uri, to: "class Bad {}"))
    await state.waitForPendingRefresh()
    #expect(try await diagnosticItems(from: state, for: uri).count == 1)
    try project.writeSource("class B")

    await state.didSave(saveNotification(for: uri))

    let sourceDiagnostics = try await diagnosticItems(from: state, for: uri)
    let diagnostic = try #require(sourceDiagnostics.first)
    #expect(diagnostic.message.contains("expected"))
    #expect(diagnostic.message.contains("Swift 6 mode"))
    #expect(diagnostic.range.lowerBound.line == 0)
    let rules = try await diagnosticItems(
      from: state,
      for: DocumentURI(project.rules)
    )
    #expect(rules.isEmpty)
  }

  @Test("Unsaved rules replace disk rules")
  func editRules() async throws {
    let project = try DiagnosticTestProject()
    let state = await makeServingState(project: project, supportsPull: true)
    let uri = DocumentURI(project.rules)

    await state.didChange(
      changeNotification(
        of: uri,
        to: """
        let app = Codebase(including: ["Sources/**"])

        Rule("public-classes", "Classes are public") {
          app.classes.violations(of: .isPublic)
        }
        """
      )
    )
    await state.waitForPendingRefresh()

    let items = try await diagnosticItems(
      from: state,
      for: DocumentURI(project.source)
    )
    #expect(items.first?.code == .string("public-classes"))
  }

  @Test("Document close restores diagnostics from disk")
  func closeDocument() async throws {
    let project = try DiagnosticTestProject(source: "final class Good {}")
    let state = await makeServingState(project: project, supportsPull: true)
    let uri = DocumentURI(project.source)
    await state.didChange(changeNotification(of: uri, to: "class Bad {}"))
    await state.waitForPendingRefresh()
    #expect(try await diagnosticItems(from: state, for: uri).count == 1)

    await state.didClose(
      DidCloseTextDocumentNotification(
        textDocument: TextDocumentIdentifier(uri)
      )
    )
    await state.waitForPendingRefresh()

    #expect(try await diagnosticItems(from: state, for: uri).isEmpty)
  }

  @Test("Unsaved text diagnostics use UTF-16 columns")
  func unsavedColumn() async throws {
    let project = try DiagnosticTestProject(source: "final class Good {}")
    let state = await makeServingState(project: project, supportsPull: true)
    let uri = DocumentURI(project.source)

    await state.didChange(
      changeNotification(of: uri, to: "let café = 1; class Bad {}")
    )
    await state.waitForPendingRefresh()

    let items = try await diagnosticItems(from: state, for: uri)
    #expect(items.first?.range.lowerBound.utf16index == 20)
  }
}
