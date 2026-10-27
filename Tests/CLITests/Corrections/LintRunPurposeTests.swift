import BylawsCore
import BylawsPaths
import BylawsTestSupport
import Foundation
import Testing
@testable import BylawsRunner

@Suite("Lint correction purpose")
struct LintRunPurposeTests {
  @Test("Check-only runs mixed checks without fix callbacks")
  func mixedChecks() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("plain") { try await app.classes.violations(of: .isFinal) }
      Rule("source") {
        let declaration = try await app.classes.only()
        let source = try declaration.source
        if source.text.contains("class lower") {
          try await app.classes.violations(of: .isFinal)
        }
      }
      Rule("formatting") {
        try await app.classes.violations("Use uppercase names") { declaration in
          try declaration.nameSource.replacement(with: declaration.name.uppercased())
        }
      }
      Rule("fix") {
        try await app.classes.violations(of: .isFinal).withFix { context in
          try context.source.slice(999..<1000).replacement(with: "Updated")
        }
      }
      """,
      "Sources/Model.swift": "class lower {}",
    ])
    let result = try await LintRunner.run(
      RuleRunConfiguration(
        root: LexicalFilePath(project.rootURL.path), sourceOnly: true
      ),
      skipTests: true
    )

    #expect(result.rules.outcome == .violations)
    #expect(result.rules.diagnostics.isEmpty)
    #expect(result.rules.reports.map(\.id.rawValue) == [
      "plain", "source", "formatting", "fix",
    ])
    for report in result.rules.reports {
      #expect(report.violations.checkedCount == 1)
      #expect(report.violations.offenders.map(\.name) == ["lower"])
      #expect(report.violations.fixes == [nil])
      #expect(report.violations.layoutCandidates.isEmpty)
    }
    #expect(result.changedPaths.isEmpty)
    #expect(try String(
      contentsOf: project.fileURL(for: "Sources/Model.swift"), encoding: .utf8
    ) == "class lower {}")
  }

  @Test("Correction preview evaluates the fix callback")
  func preview() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("classes") {
        try await app.classes.violations(of: .isFinal).withFix { context in
          try context.source.slice(999..<1000).replacement(with: "Updated")
        }
      }
      """,
      "Sources/Model.swift": "class Model {}",
    ])
    let result = try await LintRunner.run(
      RuleRunConfiguration(
        root: LexicalFilePath(project.rootURL.path), sourceOnly: true
      ),
      skipTests: true, corrections: .preview
    )

    #expect(result.rules.outcome == .invalidRules)
    #expect(result.rules.diagnostics.count == 1)
    #expect(result.changedPaths.isEmpty)
    #expect(try String(
      contentsOf: project.fileURL(for: "Sources/Model.swift"), encoding: .utf8
    ) == "class Model {}")
  }

  @Test("Application discards check-only cache and verifies changed source")
  func application() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("classes") {
        try await app.classes.violations(of: .isFinal).withFix { context in
          try context.source.slice(0..<0).replacement(with: "final ")
        }
      }
      """,
      "Sources/Model.swift": "class Model {}",
    ])
    let cache = project.rootURL.appendingPathComponent("Cache")
    var configuration = RuleRunConfiguration(
      root: LexicalFilePath(project.rootURL.path), sourceOnly: true,
      parseCachePolicy: .enabled(
        directory: cache, cachesTemporaryRoots: true
      )
    )
    let check = try await LintRunner.run(configuration, skipTests: true)
    let checked = try #require(check.rules.reports.first)
    #expect(checked.violations.fixes == [nil])
    _ = try resultCacheFile(in: cache)
    configuration.changedPaths = ["Sources/Unrelated.swift"]
    let result = try await LintRunner.run(
      configuration,
      skipTests: true, corrections: .apply
    )

    #expect(result.rules.outcome == .passed)
    #expect(result.changedPaths == [
      project.fileURL(for: "Sources/Model.swift").path,
    ])
    let report = try #require(result.rules.reports.first)
    #expect(report.violations.checkedCount == 1)
    #expect(report.violations.offenders.isEmpty)
    #expect(try String(
      contentsOf: project.fileURL(for: "Sources/Model.swift"), encoding: .utf8
    ) == "final class Model {}")
  }
}
