import BylawsCore
import BylawsInterpreter
import BylawsPaths
import BylawsTestSupport
import Foundation
import Testing

@Suite("Folder rule discovery")
struct FolderDiscoveryTests {
  @Test(
    "Find local rules without package manifests",
    .bug("https://github.com/theblixguy/swift-bylaws/issues/12"),
    arguments: ["MODULE.bazel", "App.xcodeproj/project.pbxproj"]
  )
  func localRules(marker: String) async throws {
    let project = try TemporaryProject(files: [
      marker: "",
      "Modules/Billing/Bylaws.swift": """
      let codebase = Codebase(including: ["Sources/**"])
      Rule("final-classes") { codebase.classes.violations(of: .isFinal) }
      """,
      "Modules/Billing/Sources/Invoice.swift": "class Invoice {}",
      "Modules/Profile/Sources/Profile.swift": "class Profile {}",
    ])

    let program = try await discoveredProgram(in: project)
    let rule = try #require(program.rules.first)

    #expect(program.rules.map(\.id) == ["final-classes"])
    #expect(try await rule.violations().offenders
      .compactMap(\.name) == ["Invoice"])
    #expect(program.rules(applyingTo: "Modules/Profile/Sources/Profile.swift")
      .isEmpty)
  }

  @Test("Find baselines without manifests or adjacent rules")
  func localBaselines() async throws {
    let project = try TemporaryProject(files: [
      "Modules/Billing/Bylaws.baseline.swift": BaselineFile.render(
        name: "billing",
        entries: []
      ),
      "Modules/Billing/Nested/Bylaws.baseline.swift": BaselineFile.render(
        name: "nested",
        entries: []
      ),
    ])

    let result = await DiscoveredBaselines
      .discovered(atRoot: project.rootURL.path)

    #expect(result.diagnostics.isEmpty)
    #expect(result.baselines.map(\.relativeDirectory) == [
      "Modules/Billing",
      "Modules/Billing/Nested",
    ])
  }

  @Test("Skip excluded folders without package manifests")
  func excludedFolders() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "RuleDiscovery(excluding: [\"Vendor\"])",
      "Vendor/Bylaws.swift": "cannot parse this",
      ".build/Bylaws.swift": "cannot parse this",
      "Modules/Billing/Bylaws.swift": """
      let codebase = Codebase(including: ["Sources/**"])
      Rule("billing") { codebase.classes.violations(of: .isFinal) }
      """,
      "Modules/Billing/Sources/Invoice.swift": "final class Invoice {}",
    ])

    let program = try await discoveredProgram(in: project)

    #expect(program.rules.map(\.id) == ["billing"])
  }

  @Test("Use unsaved folder rules without package manifests")
  func editorRules() async throws {
    let project = try TemporaryProject(files: [
      "Modules/Billing/Bylaws.swift": "cannot parse this",
      "Modules/Billing/Sources/Invoice.swift": "class Invoice {}",
    ])
    let program = await RuleProgram.discovered(
      atRoot: LexicalFilePath(project.rootURL.path),
      parseCachePolicy: .disabled,
      overlay: SourceOverlay([
        project.fileURL(for: "Modules/Billing/Bylaws.swift").path: """
        let codebase = Codebase(including: ["Sources/**"])
        Rule("classes") { codebase.classes.violations(of: .isFinal) }
        """,
      ])
    )
    let rule = try #require(program.rules.first)

    #expect(program.diagnostics.isEmpty)
    #expect(try await rule.violations().offenders
      .compactMap(\.name) == ["Invoice"])
  }
}
