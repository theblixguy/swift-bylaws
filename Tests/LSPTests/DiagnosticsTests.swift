import BylawsCore
import BylawsPaths
import BylawsRunner
import Clocks
import Foundation
import LanguageServerProtocol
import Testing
@testable import BylawsLSP

@Suite("LSP diagnostics")
struct DiagnosticsTests {
  @Test("Push diagnostics contain rule violations")
  func pushDiagnostics() async throws {
    let project = try DiagnosticTestProject()
    let connection = TestConnection()
    let state = BylawsLanguageServerState(
      clock: UnimplementedClock(),
      client: connection
    )
    _ = await state.initialize(
      initializeRequest(root: project.root, supportsPull: false)
    )

    await state.initialized()

    let published = try #require(
      connection.publishedDiagnostics.last {
        $0.uri.pseudoPath == project.source.path
      }
    )
    let diagnostic = try #require(published.diagnostics.first)
    #expect(diagnostic.code == .string("final-classes"))
    #expect(diagnostic.message.contains("Bad violates 'Classes are final'"))
  }

  @Test("Pull diagnostics contain rule violations")
  func pullDiagnostics() async throws {
    let project = try DiagnosticTestProject()
    let state = BylawsLanguageServerState(
      clock: UnimplementedClock(),
      client: TestConnection()
    )
    _ = await state.initialize(
      initializeRequest(root: project.root, supportsPull: true)
    )

    let report = await state.diagnostics(
      for: DocumentDiagnosticsRequest(
        textDocument: TextDocumentIdentifier(
          DocumentURI(project.source)
        )
      )
    )

    guard case let .full(fullReport) = report else {
      Issue.record("Expected a full diagnostic report")
      return
    }
    let diagnostic = try #require(fullReport.items.first)
    #expect(diagnostic.code == .string("final-classes"))
  }

  @Test("Workspace folder sets project root")
  func workspaceFolderRoot() async throws {
    let project = try DiagnosticTestProject()
    let state = BylawsLanguageServerState(
      clock: UnimplementedClock(),
      client: TestConnection()
    )
    _ = await state.initialize(
      InitializeRequest(
        rootURI: nil,
        capabilities: ClientCapabilities(
          textDocument: TextDocumentClientCapabilities(diagnostic: .init())
        ),
        workspaceFolders: [WorkspaceFolder(uri: DocumentURI(project.root))]
      )
    )

    let report = await state.diagnostics(
      for: DocumentDiagnosticsRequest(
        textDocument: TextDocumentIdentifier(DocumentURI(project.source))
      )
    )

    guard case let .full(fullReport) = report else {
      Issue.record("Expected a full diagnostic report")
      return
    }
    #expect(fullReport.items.first?.code == .string("final-classes"))
  }

  @Test("Diagnostic columns use UTF-16 offsets")
  func utf16Column() async throws {
    let project = try DiagnosticTestProject(
      source: "let café = 1; class Bad {}"
    )
    let state = BylawsLanguageServerState(
      clock: UnimplementedClock(),
      client: TestConnection()
    )
    _ = await state.initialize(
      initializeRequest(root: project.root, supportsPull: true)
    )

    let report = await state.diagnostics(
      for: DocumentDiagnosticsRequest(
        textDocument: TextDocumentIdentifier(DocumentURI(project.source))
      )
    )

    guard case let .full(fullReport) = report else {
      Issue.record("Expected a full diagnostic report")
      return
    }
    let diagnostic = try #require(fullReport.items.first)
    #expect(diagnostic.range.lowerBound.utf16index == 20)
  }

  @Test("Saved file replaces earlier diagnostics")
  func savedSource() async throws {
    let project = try DiagnosticTestProject()
    let connection = TestConnection()
    let state = BylawsLanguageServerState(
      clock: UnimplementedClock(),
      client: connection
    )
    _ = await state.initialize(
      initializeRequest(root: project.root, supportsPull: false)
    )
    await state.initialized()
    try project.writeSource("final class Good {}")

    let uri = DocumentURI(project.source)
    await state.didSave(saveNotification(for: uri))

    let published = try #require(connection.publishedDiagnostics.last)
    #expect(published.uri == uri)
    #expect(published.diagnostics.isEmpty)
  }

  @available(macOS 13, iOS 16, *)
  @Test(
    "Overlapping refreshes keep latest diagnostics",
    .timeLimit(.minutes(3))
  )
  func overlappingRefreshes() async throws {
    let olderProject = try DiagnosticTestProject()
    let control = DiagnosticRefreshControl()
    let sourcePath = olderProject.source.path
    let state = BylawsLanguageServerState(
      clock: UnimplementedClock(),
      client: TestConnection(),
      runner: RuleRunning(
        run: { configuration throws(CancellationError) in
          let requestID = await control.beginRequest()
          let result = RuleRunResult.mock(
            rootPath: configuration.root.string,
            diagnosticAt: requestID == 0 ? sourcePath : nil
          )
          await control.suspend(requestID)
          return result
        },
        discardCaches: { _ in }
      )
    )
    _ = await state.initialize(
      initializeRequest(root: olderProject.root, supportsPull: true)
    )
    let uri = DocumentURI(olderProject.source)

    let olderRefresh = Task { @concurrent in
      await state.didSave(saveNotification(for: uri))
    }
    await control.waitForSuspendedRequests(1)
    let newerRefresh = Task { @concurrent in
      await state.didSave(saveNotification(for: uri))
    }
    await control.waitForSuspendedRequests(2)

    await control.resumeRequest(1)
    await newerRefresh.value
    await control.resumeRequest(0)
    await olderRefresh.value

    let report = await state.diagnostics(
      for: DocumentDiagnosticsRequest(
        textDocument: TextDocumentIdentifier(uri)
      )
    )
    guard case let .full(fullReport) = report else {
      Issue.record("Expected a full diagnostic report")
      return
    }
    #expect(fullReport.items.isEmpty)
  }

  @Test("Missing rules return empty diagnostics")
  func noRules() async throws {
    let project = try DiagnosticTestProject(rules: nil)
    let state = BylawsLanguageServerState(
      clock: UnimplementedClock(),
      client: TestConnection()
    )
    _ = await state.initialize(
      initializeRequest(root: project.root, supportsPull: true)
    )

    let report = await state.diagnostics(
      for: DocumentDiagnosticsRequest(
        textDocument: TextDocumentIdentifier(DocumentURI(project.source))
      )
    )

    guard case let .full(fullReport) = report else {
      Issue.record("Expected a full diagnostic report")
      return
    }
    #expect(fullReport.items.isEmpty)
  }

  @Test("Rules file removal clears pushed diagnostics")
  func removedRules() async throws {
    let project = try DiagnosticTestProject()
    let connection = TestConnection()
    let state = BylawsLanguageServerState(
      clock: UnimplementedClock(),
      client: connection
    )
    _ = await state.initialize(
      initializeRequest(root: project.root, supportsPull: false)
    )
    await state.initialized()
    try project.removeRules()

    await state.didSave(
      DidSaveTextDocumentNotification(
        textDocument: TextDocumentIdentifier(DocumentURI(project.source))
      )
    )

    let published = try #require(connection.publishedDiagnostics.last)
    #expect(published.uri == DocumentURI(project.source))
    #expect(published.diagnostics.isEmpty)
  }

  @available(macOS 13, iOS 16, *)
  @Test(
    "Rule syntax errors clear pushed source diagnostics",
    .timeLimit(.minutes(3))
  )
  func pushRuleSyntaxError() async throws {
    let project = try DiagnosticTestProject()
    let connection = TestConnection()
    let state = BylawsLanguageServerState(
      clock: UnimplementedClock(),
      client: connection
    )
    _ = await state.initialize(
      initializeRequest(root: project.root, supportsPull: false)
    )
    await state.initialized()
    let uri = DocumentURI(project.source)
    #expect(connection.publishedDiagnostics.last?.diagnostics.count == 1)
    try project.writeRules(DiagnosticTestProject.invalidRules)

    await state.didSave(saveNotification(for: uri))

    let source = connection.publishedDiagnostics.last { $0.uri == uri }
    #expect(source?.diagnostics.isEmpty == true)
    let rules = connection.publishedDiagnostics.last {
      $0.uri == DocumentURI(project.rules)
    }
    #expect(rules?.diagnostics.count == 1)
  }

  @Test("Cancelled refresh keeps previous diagnostics")
  func cancelledRefresh() async throws {
    let project = try DiagnosticTestProject()
    let connection = TestConnection()
    let sequence = RefreshSequence()
    let state = BylawsLanguageServerState(
      clock: UnimplementedClock(),
      client: connection,
      runner: RuleRunning(
        run: { configuration throws(CancellationError) in
          if await sequence
            .shouldFail()
          {
            throw CancellationError()
          }
          var configuration = configuration
          configuration
            .parseCachePolicy = .disabled
          return try await RuleRunner
            .run(configuration)
        },
        discardCaches: RuleRunner
          .discardCaches(under:)
      )
    )
    _ = await state.initialize(
      initializeRequest(root: project.root, supportsPull: false)
    )
    await state.initialized()
    let publicationCount = connection.publishedDiagnostics.count
    #expect(connection.publishedDiagnostics.last?.diagnostics.count == 1)

    await state.didSave(saveNotification(for: DocumentURI(project.source)))

    #expect(connection.publishedDiagnostics.count == publicationCount)
    #expect(connection.publishedDiagnostics.last?.diagnostics.count == 1)
  }

  @Test("Save discards project caches")
  func cacheRemovalOnSave() async throws {
    let project = try DiagnosticTestProject()
    let discarded = DiscardedRoots()
    let state = BylawsLanguageServerState(
      clock: UnimplementedClock(),
      client: TestConnection(),
      runner: RuleRunning(
        run: { configuration throws(CancellationError) in
          var configuration = configuration
          configuration
            .parseCachePolicy = .disabled
          return try await RuleRunner
            .run(configuration)
        },
        discardCaches: {
          await discarded.record($0)
        }
      )
    )
    _ = await state.initialize(
      initializeRequest(root: project.root, supportsPull: false)
    )
    await state.initialized()

    await state.didSave(saveNotification(for: DocumentURI(project.source)))

    let roots = await discarded.roots
    #expect(roots == [LexicalFilePath(project.root.path).string])
  }

  @Test("Rule syntax errors return new empty source report")
  func pullRuleSyntaxError() async throws {
    let project = try DiagnosticTestProject()
    let state = BylawsLanguageServerState(
      clock: UnimplementedClock(),
      client: TestConnection()
    )
    _ = await state.initialize(
      initializeRequest(root: project.root, supportsPull: true)
    )
    let uri = DocumentURI(project.source)
    let first = await state.diagnostics(
      for: DocumentDiagnosticsRequest(
        textDocument: TextDocumentIdentifier(uri)
      )
    )
    guard case let .full(firstReport) = first else {
      Issue.record("Expected a full diagnostic report")
      return
    }
    let resultID = try #require(firstReport.resultId)
    #expect(firstReport.items.count == 1)
    try project.writeRules(DiagnosticTestProject.invalidRules)

    await state.didSave(saveNotification(for: uri))
    let refreshed = await state.diagnostics(
      for: DocumentDiagnosticsRequest(
        textDocument: TextDocumentIdentifier(uri),
        previousResultId: resultID
      )
    )

    guard case let .full(refreshedReport) = refreshed else {
      Issue.record("Expected a new full diagnostic report")
      return
    }
    #expect(refreshedReport.resultId != resultID)
    #expect(refreshedReport.items.isEmpty)
  }
}

private actor DiscardedRoots {
  private(set) var roots: [String] = []

  func record(_ root: String) {
    roots.append(root)
  }
}

private actor RefreshSequence {
  private var requestCount = 0

  func shouldFail() -> Bool {
    defer { requestCount += 1 }
    return requestCount > 0
  }
}
