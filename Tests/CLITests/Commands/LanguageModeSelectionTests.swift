import BylawsInterpreter
import BylawsPaths
import BylawsRunner
import BylawsTestSupport
import Foundation
import Testing

@Suite("CLI language-mode selection")
struct CLILanguageModeSelectionTests {
  @Test("CLI applies selected project settings", arguments: [
    (".automatic(.swiftPM)", "5.9", "6.0", 1, 0),
    (".automatic(.xcode)", "6.0", "5.0", 1, 0),
    (".automatic([.swiftPM, .xcode])", "5.9", "6.0", 1, 0),
    (".automatic([.xcode, .swiftPM])", "5.9", "6.0", 1, 0),
    (".automatic([.swiftPM, .swiftPM])", "5.9", "6.0", 1, 0),
    (".automatic([])", "5.9", "5.0", 0, 1),
  ])
  func projectSelection(
    selection: String,
    toolsVersion: String,
    xcodeVersion: String,
    reportCount: Int,
    diagnosticCount: Int
  ) async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "// swift-tools-version: \(toolsVersion)\nlet package = Package(name: \"App\", targets: [.target(name: \"App\")])",
      "App.xcodeproj/project.pbxproj": xcodeProjectSource(
        targetSettings: "SWIFT_VERSION = \(xcodeVersion);"
      ),
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"], swiftLanguageMode: \(selection))
      Rule("final-classes") { app.classes.violations(of: .isFinal) }
      """,
      "Sources/App/App.swift": "@available (swift, obsoleted: 1.0)\nfinal class App {}",
    ])
    let result = try await RuleRunner.run(RuleRunConfiguration(
      root: LexicalFilePath(project.rootURL.path), sourceOnly: true
    ))

    #expect(result.reports.count == reportCount)
    #expect(result.diagnostics.count == diagnosticCount)
    #expect(result.diagnostics.allSatisfy {
      $0.message.contains("extraneous whitespace")
        && $0.message.contains("Swift 6 mode")
    })
  }
}
