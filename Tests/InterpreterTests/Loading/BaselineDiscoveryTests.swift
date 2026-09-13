import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Baseline discovery")
struct BaselineDiscoveryTests {
  @Test("Discovery finds baselines at the root and beside a module manifest")
  func discoversRootAndModuleBaselines() async throws {
    let project = try makeProject()

    let found = await DiscoveredBaselines
      .discovered(atRoot: project.rootURL.path)
      .baselines
    #expect(Set(found.map(\.relativeDirectory)) == ["", "Modules/Feature"])
  }

  @Test("A module baseline accepts only offenders from its subtree")
  func scopesModuleEntriesToTheirSubtree() async throws {
    let project = try makeProject()

    let program = try await discoveredProgram(in: project)
    let rule = try #require(program.rules.first)

    let filtered = try await rule.violations().removingOffenders(
      acceptedBy: await DiscoveredBaselines
        .discovered(atRoot: project.rootURL.path)
        .baselines,
      for: rule.id,
      under: project.rootURL.path
    )

    #expect(filtered.offenders.compactMap(\.name).sorted() == [
      "FeatureViewModel", "FreshViewModel",
    ])
    let survivingFeature = try #require(
      filtered.offenders.first { $0.name == "FeatureViewModel" }
    )
    #expect(
      survivingFeature.location.filePath.contains("App/Feature.swift")
    )
  }

  @Test("A module baseline rejects a violation from a prefix-sharing sibling")
  func moduleBaselineKeepsPrefixSharingSibling() async throws {
    let project = try makeProject(extraFiles: [
      "Modules/FeatureKit/Package.swift": "// swift-tools-version: 6.0",
      "Modules/FeatureKit/Sources/Feature.swift": "class FeatureViewModel {}",
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)
    let rule = try #require(program.rules.first)

    let filtered = try await rule.violations().removingOffenders(
      acceptedBy: await DiscoveredBaselines
        .discovered(atRoot: project.rootURL.path)
        .baselines,
      for: rule.id,
      under: project.rootURL.path
    )

    let survivors = filtered.offenders.filter { $0.name == "FeatureViewModel" }
    #expect(survivors.count == 2)
    #expect(
      survivors.contains {
        $0.location.filePath.contains("Modules/FeatureKit/")
      }
    )
  }

  @Test("A module baseline applies through a symlinked project root")
  func moduleBaselineAppliesThroughSymlink() async throws {
    let project = try makeProject()
    let alias = "\(project.rootURL.path)-alias"
    try FileManager.default.createSymbolicLink(
      atPath: alias,
      withDestinationPath: project.rootURL.path
    )
    defer { try? FileManager.default.removeItem(atPath: alias) }

    let program = await RuleProgram.discovered(atRoot: alias)
    let rule = try #require(program.rules.first)
    let filtered = try await rule.violations().removingOffenders(
      acceptedBy: await DiscoveredBaselines.discovered(atRoot: alias)
        .baselines,
      for: rule.id,
      under: alias
    )

    #expect(rule.location.filePath.hasPrefix(alias))
    #expect(filtered.offenders.compactMap(\.name).sorted() == [
      "FeatureViewModel", "FreshViewModel",
    ])
  }

  @Test("Discovery finds a baseline without an adjacent rules file")
  func discoversWithoutRulesFile() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.baseline.swift": BaselineFile.render(
        name: "project",
        entries: [
          Baseline.Entry(
            rule: "viewmodel-inheritance",
            declaration: "HomeViewModel",
            file: "App/Screens.swift"
          ),
        ]
      ),
      "App/Screens.swift": "class HomeViewModel {}",
    ])

    let found = await DiscoveredBaselines
      .discovered(atRoot: project.rootURL.path)
      .baselines
    #expect(found.map(\.relativeDirectory) == [""])
    #expect(found.first?.entries.count == 1)
  }

  @Test("An unreadable baseline file reports a diagnostic")
  func unreadableBaselineReportsDiagnostic() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.baseline.swift/placeholder.txt": "a directory, not a file",
    ])

    let found = await DiscoveredBaselines
      .discovered(atRoot: project.rootURL.path)
    #expect(found.baselines.isEmpty)
    #expect(found.diagnostics.contains {
      $0.message.contains("cannot read")
    })
  }

  @Test("An explicit file replaces the discovered baselines")
  func explicitFileReplacesDiscovery() async throws {
    let project = try makeProject(extraFiles: [
      "elsewhere.swift": BaselineFile.render(name: "explicit", entries: []),
    ])

    let accepted = await DiscoveredBaselines.accepted(
      from: "\(project.rootURL.path)/elsewhere.swift",
      atRoot: project.rootURL.path
    ).baselines

    #expect(accepted.map(\.path) == ["\(project.rootURL.path)/elsewhere.swift"])
    let explicit = try #require(accepted.first)
    #expect(explicit.entries.isEmpty)
  }

  private func makeProject(
    extraFiles: [String: String] = [:]
  ) throws -> TemporaryProject {
    var files = [
      "Bylaws.swift": """
      let app = Codebase(including: ["App/**", "Modules/**"])

      Rule("viewmodel-inheritance", "ViewModels inherit from BaseViewModel") {
        app.classes.suffixed("ViewModel").violations(of: .inherits(from: "BaseViewModel"))
      }
      """,
      "Bylaws.baseline.swift": BaselineFile.render(
        name: "project",
        entries: [
          Baseline.Entry(
            rule: "viewmodel-inheritance",
            declaration: "HomeViewModel",
            file: "App/Screens.swift"
          ),
        ]
      ),
      "App/Screens.swift": """
      class HomeViewModel {}
      class FreshViewModel {}
      """,
      "App/Feature.swift": "class FeatureViewModel {}",
      "Modules/Feature/Package.swift": "// swift-tools-version: 6.0",
      "Modules/Feature/Bylaws.baseline.swift": BaselineFile.render(
        name: "feature",
        entries: [
          Baseline.Entry(
            rule: "viewmodel-inheritance",
            declaration: "FeatureViewModel",
            file: "Modules/Feature/Sources/Feature.swift"
          ),
        ]
      ),
      "Modules/Feature/Sources/Feature.swift": "class FeatureViewModel {}",
    ]
    for (path, contents) in extraFiles {
      files[path] = contents
    }
    return try TemporaryProject(files: files)
  }
}
