import BylawsCore
import BylawsInterpreter
import BylawsPaths
import BylawsRunner
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("CLI language modes")
struct CLILanguageModeTests {
  @Test("Portable rules enable Xcode discovery", arguments: [
    "Rule(\"final-classes\") { app.classes.violations(of: .isFinal) }",
    "let rules: [Rule] = [Rule(\"final-classes\") { app.classes.violations(of: .isFinal) }]",
  ])
  func xcodeDiscovery(rule: String) async throws {
    let project = try TemporaryProject(files: [
      "App.xcodeproj/project.pbxproj": xcodeProjectSource(),
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"], swiftLanguageMode: .automatic(.xcode))
      \(rule)
      """,
      "Sources/App.swift": "@available (swift, obsoleted: 1.0)\nfinal class App {}",
    ])
    let result = try await RuleRunner.run(RuleRunConfiguration(
      root: LexicalFilePath(project.rootURL.path), sourceOnly: true
    ))

    #expect(result.diagnostics.isEmpty)
    #expect(result.reports.count == 1)
  }

  @Test("Portable rules skip disabled Xcode discovery", arguments: [
    "", ", swiftLanguageMode: .automatic(.swiftPM)",
  ])
  func disabledDiscovery(argument: String) async throws {
    let project = try TemporaryProject(files: [
      "App.xcodeproj/project.pbxproj": "not a property list",
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"]\(argument))
      Rule("final-classes") { app.classes.violations(of: .isFinal) }
      """,
      "Sources/App.swift": "final class App {}",
    ])
    let result = try await RuleRunner.run(RuleRunConfiguration(
      root: LexicalFilePath(project.rootURL.path), sourceOnly: true
    ))

    #expect(result.diagnostics.isEmpty)
    #expect(result.reports.count == 1)
  }

  @Test(
    "Language selection rejects unsupported expressions",
    arguments: [
      "1", "\"v5\"", "nil", ".v7", ".automatic", ".automatic()",
      ".automatic(.unknown)", ".automatic([.swiftPM, .unknown])",
      ".automatic(.swiftPM, .xcode)", ".automatic(projects: .swiftPM)",
      ".automatic(.xcode) {}", ".automatic([.swiftPM, [.xcode]])",
      ".automatic(Other.swiftPM)", ".v5()",
    ]
  )
  func discoveryArgument(argument: String) async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(swiftLanguageMode: \(argument))
      Rule("final-classes") { app.classes.violations(of: .isFinal) }
      """,
      "App.swift": "final class App {}",
    ])
    let result = try await RuleRunner.run(RuleRunConfiguration(
      root: LexicalFilePath(project.rootURL.path), sourceOnly: true
    ))

    #expect(result.diagnostics.contains {
      $0.message == "Codebase takes .v4, .v5, .v6 or .automatic(...) for swiftLanguageMode"
    })
    #expect(result.reports.isEmpty)
  }

  @Test("CLI reads package mode before checking rules")
  func packageMode() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "// swift-tools-version: 5.9\nlet package = Package(name: \"App\", targets: [.target(name: \"App\")])",
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("final-classes") { app.classes.violations(of: .isFinal) }
      """,
      "Sources/App/App.swift": "@available (swift, obsoleted: 1.0)\nfinal class App {}",
    ])
    let result = try await RuleRunner.run(RuleRunConfiguration(
      root: LexicalFilePath(project.rootURL.path), sourceOnly: true
    ))

    #expect(result.diagnostics.isEmpty)
    #expect(result.reports.count == 1)
  }

  @Test("Portable rules apply explicit language mode", arguments: [
    "Rule(\"final-classes\") { app.classes.violations(of: .isFinal) }",
    "let rules: [Rule] = [Rule(\"final-classes\") { app.classes.violations(of: .isFinal) }]",
  ])
  func explicitMode(rule: String) async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"], swiftLanguageMode: .v5)
      \(rule)
      """,
      "Sources/App.swift": "@available (swift, obsoleted: 1.0)\nfinal class App {}",
    ])
    let result = try await RuleRunner.run(RuleRunConfiguration(
      root: LexicalFilePath(project.rootURL.path), sourceOnly: true
    ))

    #expect(result.diagnostics.isEmpty)
    #expect(result.reports.count == 1)
  }

  @Test("Syntax errors name source position and language mode")
  func syntaxPosition() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"], swiftLanguageMode: .v6)
      Rule("final-classes") { app.classes.violations(of: .isFinal) }
      """,
      "Sources/App.swift": "@available (swift, obsoleted: 1.0)\nfinal class App {}",
    ])
    let result = try await RuleRunner.run(RuleRunConfiguration(
      root: LexicalFilePath(project.rootURL.path), sourceOnly: true
    ))

    let diagnostic = try #require(result.diagnostics.first)
    #expect(diagnostic.location.filePath == project
      .fileURL(for: "Sources/App.swift").path)
    #expect(diagnostic.location.line == 1)
    #expect(diagnostic.message.contains("extraneous whitespace"))
    #expect(diagnostic.message.contains("Swift 6 mode"))
  }
}
