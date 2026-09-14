import Bylaws
import Testing

@Suite("Package conventions", .codebase(.bylaws), .tags(.layering))
struct BylawsOwnRulesTests {
  @Test("Package dependencies match source imports")
  func manifestMatchesImports() async throws {
    let codebase = Codebase(
      root: .automatic(),
      including: ["Sources/**", "Tests/**", "Plugins/**"],
      excluding: ["**/.build/**"],
      swiftLanguageMode: .v6
    )
    let targetsWithoutSwiftSources = ["CIndexStore"]
    let result = try await codebase.checkPackageDependencies(
      ignoring: targetsWithoutSwiftSources
    )
    #expect(result.violations.isEmpty)
    #expect(result.unused.isEmpty)
    #expect(!result.isComplete)
    #expect(
      result.unresolvedManifestValues.allSatisfy { value in
        [
          "binaryTarget",
          "conditional target declarations",
          "pluginTool.dependency",
          "swift-docc-plugin",
        ].contains { value.expression.contains($0) }
      }
    )
  }

  @Test("Dependencies use exact versions except SwiftSyntax")
  func packageDependenciesUseRequiredVersions() async throws {
    let manifest = try await Codebase.bylaws.packageManifest
    let swiftSyntaxDependencies = manifest.dependencies(named: "swift-syntax")
    #expect(swiftSyntaxDependencies.possibleValues.count == 1)
    let swiftSyntax = try #require(swiftSyntaxDependencies.possibleValues.first)
    #expect(
      swiftSyntax.requirement
        == .range(from: .init(602, 0, 0), upTo: .init(604, 0, 0))
    )
    let otherNonExactDependencies = manifest.dependencies.possibleValues
      .filter {
        $0.name != "swift-syntax" && !$0.requirement.isExactVersion
      }
    #expect(otherNonExactDependencies.isEmpty)
    #expect(
      manifest.dependencies.unresolvedValues.allSatisfy {
        $0.expression.contains("exact:")
      }
    )
  }

  @Test("Library and executable targets have test coverage")
  func libraryAndExecutableTargetsHaveTestCoverage() async throws {
    let manifest = try await Codebase.bylaws.packageManifest
    let processTestedTargets = ["bylaws-lsp"]
    let targetsWithoutTests = manifest.targets(
      includingConditionalDependencies: true
    ).possibleValues.filter { target in
      !processTestedTargets.contains(target.name)
        && manifest.testTargets(
          dependingOn: target,
          includingConditionalDependencies: true
        ).possibleValues.isEmpty
    }
    #expect(targetsWithoutTests.isEmpty)
  }

  @Test("Swift targets use project language settings")
  func swiftTargetsUseProjectLanguageSettings() async throws {
    let manifest = try await Codebase.bylaws.packageManifest
    let nonSwiftTargets = ["CIndexStore"]
    let requiredSettings: Set<PackageManifest.Target.Setting.Value> = [
      .strictMemorySafety,
      .defaultIsolation(nil),
      .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
      .enableUpcomingFeature("InferIsolatedConformances"),
      .enableUpcomingFeature("InternalImportsByDefault"),
      .enableUpcomingFeature("MemberImportVisibility"),
      .enableUpcomingFeature("ExistentialAny"),
    ]
    let targetsWithoutRequiredSettings = manifest.targets.possibleValues
      .filter { target in
        !nonSwiftTargets.contains(target.name)
          && target.kind != .binary
          && target.kind != .plugin
          && !requiredSettings.isSubset(
            of: Set(
              target.buildSettings.knownValues
                .filter { $0.condition == nil }
                .map(\.value)
            )
          )
      }
    #expect(targetsWithoutRequiredSettings.isEmpty)
  }
}
