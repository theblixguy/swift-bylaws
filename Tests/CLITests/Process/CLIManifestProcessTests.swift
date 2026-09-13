import Testing

@Suite("Bylaws manifest process")
struct CLIManifestProcessTests {
  @Test(
    "Portable rules can read package manifest values",
    arguments: [
      ManifestRuleCase(
        testDescription: "Dependency requirements",
        predicate: """
        allDependenciesArePinned(manifest.dependencies)
          && manifest.dependencies(
            named: "swift-syntax"
          ).knownValues.contains {
            $0.sourceKind == .url
              && $0.sourceLocation.hasSuffix("swift-syntax.git")
              && ($0.requirement.majorVersion ?? 0) > 500
              && $0.requirement.minimumVersion?.description == "600.0.1"
              && $0.traits.knownValues.contains { $0.kind == .defaults }
          }
        """
      ),
      ManifestRuleCase(
        testDescription: "Target configuration and relationships",
        predicate: """
        manifest.targets.knownValues.contains { target in
          target.name == "App"
            && target.sources.kind == .explicit
            && (target.sources.paths?.knownValues.contains("App.swift") ?? false)
            && target.resources.knownValues.contains {
              $0.rule == .copy && $0.path == "Config.json"
            }
            && target.buildSettings.knownValues.contains {
              $0.tool == .swift
                && $0.valueKind == .enableUpcomingFeature
                && $0.value == "ExistentialAny"
                && !$0.usesUnsafeFlags
            }
            && manifest.products(containing: target).knownValues.contains {
              $0.name == "Example"
            }
            && manifest.testTargets(
              dependingDirectlyOn: target
            ).knownValues.contains { $0.name == "AppTests" }
            && manifest.directTargetDependencies(
              of: target,
              includingConditionalDependencies: true
            ).conditionalValues.contains { $0.name == "Core" }
            && manifest.transitiveTargetDependencies(
              of: target,
              includingConditionalDependencies: true
            ).conditionalValues.contains { $0.name == "Core" }
        }
        """
      ),
      ManifestRuleCase(
        testDescription: "Package metadata",
        predicate: """
        manifest.platforms.knownValues.contains {
          $0.name == "macOS" && $0.minimumVersion.description == "14"
        } && manifest.products.knownValues.contains {
          $0.name == "Example"
            && $0.kind == .library
            && $0.linkage == .static
        } && manifest.traits.knownValues.contains {
          $0.name == "Feature"
            && $0.enabledTraitNames.contains("Foundation")
        } && manifest.targets().knownValues.contains {
          $0.name == "App"
        } && manifest.targets(
          includingConditionalDependencies: true
        ).conditionalValues.contains { $0.name == "Core" }
        """
      ),
      ManifestRuleCase(
        testDescription: "Plugin and special target details",
        predicate: """
        manifest.targets.knownValues.contains { target in
          target.name == "DocsPlugin"
            && target.isPlugin
            && target.pluginCapability?.kind == .command
            && target.pluginCapability?.intent?.kind
              == .documentationGeneration
            && (target.pluginCapability?.permissions.contains { permission in
              permission.kind == .allowNetworkConnections
                && permission.reason == "Connects to the preview server."
                && permission.networkScope?.kind == .local
                && (permission.networkScope?.ports?.values.contains(8080)
                  ?? false)
            } ?? false)
        } && manifest.targets.knownValues.contains {
          $0.name == "CLib"
            && $0.pkgConfig == "libexample"
            && $0.providers.knownValues.contains { provider in
              provider.kind == .brew && provider.packages.contains("example")
            }
        } && manifest.targets.knownValues.contains {
          $0.name == "RemoteSDK"
            && $0.binarySource?.kind == .remote
            && $0.binarySource?.sourceLocation
              == "https://example.com/sdk.zip"
            && $0.binarySource?.checksum == "abc123"
        }
        """
      ),
    ]
  )
  func portableManifestRule(_ testCase: ManifestRuleCase) throws {
    let project = try CLIProcessProject(
      source: "public struct App {}",
      rules: """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])

      func allDependenciesArePinned(
        _ dependencies: ManifestList<PackageManifest.Dependency>
      ) -> Bool {
        dependencies.knownValues.allSatisfy(\\.requirement.isExactVersion)
      }

      let projectRules: [Rule] = [
        Rule("manifest", "The package manifest follows the project policy") {
          let manifest = try await app.packageManifest
          let matchesManifest = manifest.isComplete && (
            \(testCase.predicate)
          )
          let files = try await app.files
          let followsPolicy = Matcher<SourceFile>("belong to a valid package") { _ in
            matchesManifest
          }
          return files.violations(of: followsPolicy)
        },
      ]
      """,
      extraFiles: ["Package.swift": Self.completeManifest]
    )

    let result = try project.run()

    #expect(result.status == 0)
    #expect(result.standardOutput.contains("Checked 1 rule: 0 violations."))
    #expect(result.standardError.isEmpty)
  }

  @Test("Portable rules can detect unresolved manifest values")
  func preservesUnresolvedManifestValues() throws {
    let project = try CLIProcessProject(
      source: "public struct App {}",
      rules: """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])

      let projectRules: [Rule] = [
        Rule("manifest-state", "Unknown manifest values stay visible") {
          let manifest = try await app.packageManifest
          let keptPartialResult = !manifest.targets.isComplete
            && manifest.targets.values == nil
            && manifest.targets.knownValues.contains { $0.name == "App" }
            && !manifest.targets.unresolvedValues.isEmpty
          let files = try await app.files
          let keepsUnknownValues = Matcher<SourceFile>(
            "belong to a manifest with explicit unknown values"
          ) { keptPartialResult }
          return files.violations(of: keepsUnknownValues)
        },
      ]
      """,
      extraFiles: [
        "Package.swift": """
        // swift-tools-version: 6.2
        import PackageDescription

        let generatedTargets = makeTargets()
        let package = Package(
          name: "Example",
          targets: [.target(name: "App")] + generatedTargets
        )
        """,
      ]
    )

    let result = try project.run()

    #expect(result.status == 0)
    #expect(result.standardOutput.contains("Checked 1 rule: 0 violations."))
    #expect(result.standardError.isEmpty)
  }

  private static let completeManifest = """
  // swift-tools-version: 6.2
  import PackageDescription

  let package = Package(
    name: "Example",
    platforms: [.macOS(.v14)],
    products: [
      .library(name: "Example", type: .static, targets: ["App"]),
    ],
    traits: [
      .trait(name: "Feature", enabledTraits: ["Foundation"]),
    ],
    dependencies: [
      .package(
        url: "https://github.com/swiftlang/swift-syntax.git",
        exact: "600.0.1"
      ),
    ],
    targets: [
      .target(name: "Core"),
      .target(
        name: "App",
        dependencies: [
          .target(name: "Core", condition: .when(platforms: [.macOS])),
        ],
        sources: ["App.swift"],
        resources: [.copy("Config.json")],
        swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
      ),
      .testTarget(name: "AppTests", dependencies: ["App"]),
      .systemLibrary(
        name: "CLib",
        pkgConfig: "libexample",
        providers: [.brew(["example"])]
      ),
      .binaryTarget(
        name: "RemoteSDK",
        url: "https://example.com/sdk.zip",
        checksum: "abc123"
      ),
      .plugin(
        name: "DocsPlugin",
        capability: .command(
          intent: .documentationGeneration(),
          permissions: [
            .allowNetworkConnections(
              scope: .local(ports: [8080]),
              reason: "Connects to the preview server."
            ),
          ]
        )
      ),
    ]
  )
  """
}

struct ManifestRuleCase:
  Codable,
  Sendable,
  CustomTestStringConvertible
{
  let testDescription: String
  let predicate: String
}
