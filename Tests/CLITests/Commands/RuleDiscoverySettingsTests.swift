import BylawsCore
import BylawsInterpreter
import BylawsPaths
import BylawsRunner
import BylawsTestSupport
import Foundation
import Testing

@Suite("Rule discovery settings in a run")
struct RuleDiscoverySettingsTests {
  @Test("Apply editor exclusions to rules and baselines")
  func editorExclusions() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "Bylaws.swift": "",
      "Sources/Model.swift": "final class Model {}",
      "Vendor/Nested/Package.swift": "",
      "Vendor/Nested/Bylaws.swift": "cannot parse this",
      "Vendor/Nested/Bylaws.baseline.swift": "cannot parse this",
    ])

    let result = try await RuleRunner.run(RuleRunConfiguration(
      root: LexicalFilePath(project.rootURL.path),
      overlay: SourceOverlay([
        project.fileURL(for: "Bylaws.swift").path: """
        RuleDiscovery(excluding: ["Vendor"])
        let app = Codebase(including: ["Sources/**"])
        Rule("final-classes") { app.classes.violations(of: .isFinal) }
        """,
      ])
    ))

    #expect(result.outcome == .passed)
    #expect(result.diagnostics.isEmpty)
    #expect(result.reports.count == 1)
  }

  @Test("Stop rule execution after repeated discovery settings")
  func repeatedDeclarations() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      RuleDiscovery(excluding: [])
      RuleDiscovery(excluding: ["Vendor"])
      let app = Codebase(including: ["Sources/**"])
      Rule("final-classes") { app.classes.violations(of: .isFinal) }
      """,
      "Sources/Model.swift": "final class Model {}",
    ])

    let result = try await RuleRunner.run(RuleRunConfiguration(
      root: LexicalFilePath(project.rootURL.path)
    ))

    #expect(result.outcome == .invalidRules)
    #expect(result.reports.isEmpty)
    #expect(result.diagnostics
      .map(\.message) == ["RuleDiscovery must be declared once"])
  }
}
