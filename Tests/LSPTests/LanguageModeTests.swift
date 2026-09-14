import BylawsTestSupport
import Clocks
import LanguageServerProtocol
import Testing
@testable import BylawsLSP

@Suite("Editor language modes")
struct EditorLanguageModeTests {
  @Test("Editor applies Xcode discovery opt-in", arguments: [
    ".automatic(.xcode)", ".automatic([.swiftPM, .xcode])",
  ])
  func xcodeDiscovery(selection: String) async throws {
    let project = try DiagnosticTestProject(
      source: "@available (swift, obsoleted: 1.0)\nclass App {}",
      rules: """
      let app = Codebase(including: ["Sources/**"], swiftLanguageMode: \(
        selection
      ))
      Rule("final-classes", "Classes are final") {
        app.classes.violations(of: .isFinal)
      }
      """,
      files: ["App.xcodeproj/project.pbxproj": xcodeProjectSource()]
    )
    let state = await makeServingState(project: project, supportsPull: true)
    let diagnostics = try await diagnosticItems(
      from: state,
      for: DocumentURI(project.source)
    )

    #expect(diagnostics.map(\.code) == [.string("final-classes")])
  }

  @Test("Editor skips Xcode settings by default")
  func defaultDiscovery() async throws {
    let project = try DiagnosticTestProject(
      files: ["App.xcodeproj/project.pbxproj": "not a property list"]
    )
    let state = await makeServingState(project: project, supportsPull: true)
    let diagnostics = try await diagnosticItems(
      from: state,
      for: DocumentURI(project.source)
    )

    #expect(diagnostics.map(\.code) == [.string("final-classes")])
  }

  @Test("Editor reads package language mode")
  func packageMode() async throws {
    let project = try DiagnosticTestProject(
      source: "@available (swift, obsoleted: 1.0)\nclass App {}",
      files: [
        "Package.swift": "// swift-tools-version: 5.9\nlet package = Package(name: \"App\", targets: [.target(name: \"App\")])",
      ]
    )
    let state = await makeServingState(project: project, supportsPull: true)
    let diagnostics = try await diagnosticItems(
      from: state,
      for: DocumentURI(project.source)
    )

    #expect(diagnostics.map(\.code) == [.string("final-classes")])
  }

  @Test("Editor applies portable codebase mode")
  func explicitMode() async throws {
    let project = try DiagnosticTestProject(
      source: "@available (swift, obsoleted: 1.0)\nclass App {}",
      rules: """
      let app = Codebase(including: ["Sources/**"], swiftLanguageMode: .v5)
      Rule("final-classes", "Classes are final") {
        app.classes.violations(of: .isFinal)
      }
      """
    )
    let state = await makeServingState(project: project, supportsPull: true)
    let diagnostics = try await diagnosticItems(
      from: state,
      for: DocumentURI(project.source)
    )

    let diagnostic = try #require(diagnostics.first)
    #expect(diagnostic.code == .string("final-classes"))
    #expect(diagnostic.message.contains("App violates"))
  }

  @Test("Editor places syntax error on source file")
  func syntaxPosition() async throws {
    let project = try DiagnosticTestProject(
      source: "@available (swift, obsoleted: 1.0)\nclass App {}"
    )
    let state = await makeServingState(project: project, supportsPull: true)
    let diagnostics = try await diagnosticItems(
      from: state,
      for: DocumentURI(project.source)
    )

    let diagnostic = try #require(diagnostics.first)
    #expect(diagnostic.message.contains("extraneous whitespace"))
    #expect(diagnostic.message.contains("Swift 6 mode"))
    #expect(diagnostic.range.lowerBound.line == 0)
  }
}
