import BylawsSemantics
import Testing

@Suite("Package manifest value resolution")
struct PackageManifestResolutionTests {
  @Test("Build settings can use an immutable list")
  func resolvesSharedSettings() throws {
    let shared = """
    [
      .strictMemorySafety(),
      .enableUpcomingFeature("ExistentialAny"),
    ]
    """
    let manifest = PackageManifest(
      source: """
      let commonSettings: [SwiftSetting] = \(shared)
      let package = Package(
        name: "App",
        targets: [.target(name: "App", swiftSettings: commonSettings)]
      )
      """
    )

    let target = try #require(manifest.targets.values?.first)
    #expect(target.buildSettings.values?.map(\.value) == [
      .strictMemorySafety,
      .enableUpcomingFeature("ExistentialAny"),
    ])
  }

  @Test("Parser returns known values from a list with one unknown part")
  func preservesPartialSettings() throws {
    let manifest = PackageManifest(
      source: """
      let commonSettings: [SwiftSetting] = [
        .strictMemorySafety(),
      ] + generatedSettings()
      let package = Package(
        name: "App",
        targets: [.target(name: "App", swiftSettings: commonSettings)]
      )
      """
    )

    let target = try #require(manifest.targets.values?.first)
    #expect(target.buildSettings.knownValues.map(\.value) == [
      .strictMemorySafety,
    ])
    #expect(!target.buildSettings.isComplete)
    #expect(!target.isComplete)
    #expect(target.buildSettings.unresolvedValues.first?.line == 3)
  }

  @Test("Manifest declarations can use immutable values")
  func resolvesBoundDeclarations() throws {
    let manifest = PackageManifest(
      source: """
      let releaseOnly: BuildSettingCondition = .when(configuration: .release)
      let isolation = MainActor.self
      let settings: [SwiftSetting] = [
        .strictMemorySafety(releaseOnly),
        .defaultIsolation(isolation),
      ]
      let app: Target = .target(name: "App", swiftSettings: settings)
      let capability: Target.PluginCapability = .buildTool()
      let plugin: Target = .plugin(
        name: "BuildPlugin",
        capability: capability
      )
      let product: Product = .library(name: "App", targets: ["App"])
      let versions: Range<Version> = "1.0.0"..<"2.0.0"
      let dependency: Package.Dependency = .package(
        url: "https://example.com/core.git",
        versions
      )
      let package = Package(
        name: "App",
        products: [product],
        dependencies: [dependency],
        targets: [app, plugin]
      )
      """
    )

    #expect(manifest.products.values?.map(\.name) == ["App"])
    let targets = try #require(manifest.targets.values)
    try #require(targets.count == 2)
    #expect(targets.map(\.name) == ["App", "BuildPlugin"])
    #expect(targets[0].buildSettings.values?.map(\.value) == [
      .strictMemorySafety,
      .defaultIsolation(.mainActor),
    ])
    #expect(
      targets[0].buildSettings.knownValues.first?.condition?.configuration
        == .release
    )
    #expect(targets[1].pluginCapability == .buildTool)
    #expect(
      manifest.dependencies.values?.first?.requirement
        == .range(from: .init(1, 0, 0), upTo: .init(2, 0, 0))
    )
  }

  @Test("Computed fields are unresolved")
  func preservesComputedScalars() throws {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        targets: [
          .target(
            name: "App",
            dependencies: [
              .product(name: "Core", package: packageName),
            ],
            packageAccess: computedAccess
          ),
        ]
      )
      """
    )

    let target = try #require(manifest.targets.values?.first)
    let dependency = try #require(target.dependencies.knownValues.first)
    #expect(dependency.name == "Core")
    #expect(!dependency.isComplete)
    #expect(!target.isComplete)
  }

  @Test("Conditional mutations make package collections incomplete")
  func detectsManifestMutations() {
    let manifest = PackageManifest(
      source: """
      let package = Package(name: "App", products: [], targets: [])
      if enabled {
        package.products.append(.library(name: "App", targets: ["App"]))
        package.targets.append(.target(name: "App"))
        package.dependencies.append(
          .package(url: "https://example.com/tool.git", exact: "1.0.0")
        )
      }
      """
    )

    #expect(!manifest.products.isComplete)
    #expect(!manifest.targets.isComplete)
    #expect(!manifest.dependencies.isComplete)
    #expect(manifest.targets.knownValues.isEmpty)
    #expect(manifest.targets.conditionalValues.map(\.name) == ["App"])
  }

  @Test("Conditional replacement makes both values conditional")
  func preservesConditionalReplacementUncertainty() {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        targets: [.target(name: "Original")]
      )
      if enabled {
        package.targets = [.target(name: "Replacement")]
      }
      """
    )

    #expect(manifest.targets.knownValues.isEmpty)
    #expect(
      Set(manifest.targets.conditionalValues.map(\.name))
        == ["Original", "Replacement"]
    )
    #expect(!manifest.targets.isComplete)
  }

  @Test("Runtime control flow makes mutations conditional")
  func detectsRuntimeControlFlow() {
    let manifest = PackageManifest(
      source: """
      let package = Package(name: "App", targets: [])
      for name in names {
        package.targets.append(.target(name: name))
      }
      switch mode {
      case .library:
        package.products.append(.library(name: "App", targets: ["App"]))
      default:
        break
      }
      """
    )

    #expect(manifest.targets.knownValues.isEmpty)
    #expect(!manifest.targets.isComplete)
    #expect(manifest.products.knownValues.isEmpty)
    #expect(!manifest.products.isComplete)
  }

  @Test("Collection mutations apply in source order")
  func replaysManifestMutations() {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        products: [.library(name: "Old", targets: ["Old"])],
        targets: [.target(name: "Core")]
      )
      package.name = "Renamed"
      package.platforms = [.macOS(.v14)]
      package.swiftLanguageModes = [.v6]
      package.targets += [.target(name: "Feature")]
      package.products = [.library(name: "App", targets: ["Feature"])]
      """
    )

    #expect(manifest.name == "Renamed")
    #expect(manifest.platforms.values == [
      .init(name: "macOS", minimumVersion: .init(14)),
    ])
    #expect(manifest.swiftLanguageModes.values == ["v6"])
    #expect(manifest.targets.values?.map(\.name) == ["Core", "Feature"])
    #expect(manifest.products.values?.map(\.name) == ["App"])
  }

  @Test(
    "Package trait assignment makes trait results incomplete"
  )
  func preservesTraitMutationUncertainty() {
    let manifest = PackageManifest(
      source: """
      let package = Package(name: "App", traits: [], targets: [])
      package.traits = [.trait(name: "Feature")]
      """
    )

    #expect(!manifest.traits.isComplete)
    #expect(!manifest.defaultTraitNames.isComplete)
  }

  @Test("Parser uses top-level Package declaration")
  func usesTopLevelPackageDeclaration() {
    let manifest = PackageManifest(
      source: """
      func makeSamplePackage() -> Package {
        Package(name: "Sample", targets: [])
      }
      let package = Package(
        name: "App",
        targets: [.target(name: "App")]
      )
      """
    )

    #expect(manifest.name == "App")
    #expect(manifest.targets.values?.map(\.name) == ["App"])
  }

  @Test("An uncalled helper does not change the package")
  func ignoresUncalledHelperMutations() {
    let manifest = PackageManifest(
      source: """
      func configure(_ package: Package) {
        package.targets.append(.target(name: "Unused"))
      }
      let package = Package(
        name: "App",
        targets: [.target(name: "App")]
      )
      """
    )

    #expect(manifest.targets.values?.map(\.name) == ["App"])
  }

  @Test("Passing the package to a helper makes mutable fields incomplete")
  func detectsPackageEscapes() {
    let manifest = PackageManifest(
      source: """
      let package = Package(name: "App", targets: [])
      configure(package)
      """
    )

    #expect(!manifest.targets.isComplete)
    #expect(!manifest.products.isComplete)
    #expect(!manifest.dependencies.isComplete)
  }

  @Test("A stored package reference makes mutable fields incomplete")
  func detectsPackageStoredInContainers() {
    let manifest = PackageManifest(
      source: """
      let package = Package(name: "App", targets: [])
      let packages = [package]
      """
    )

    #expect(!manifest.targets.isComplete)
    #expect(!manifest.products.isComplete)
    #expect(!manifest.dependencies.isComplete)
  }

  @Test(
    "A target reference mutation makes the target list incomplete",
    arguments: [
      """
      let app: Target = .target(name: "App")
      app.dependencies.append("Core")
      let package = Package(name: "App", targets: [app])
      """,
      """
      let app: Target = .target(name: "App")
      let package = Package(name: "App", targets: [app])
      package.targets[0].dependencies.append("Core")
      """,
    ]
  )
  func detectsTargetReferenceMutations(source: String) {
    let manifest = PackageManifest(source: source)

    #expect(!manifest.targets.isComplete)
    #expect(manifest.targets.knownValues.isEmpty)
    #expect(manifest.targets.conditionalValues.map(\.name) == ["App"])
  }

  @Test("A helper that changes an unrelated value leaves targets complete")
  func ignoresUnrelatedCollectionMutations() {
    let manifest = PackageManifest(
      source: """
      struct Metrics {
        var dependencies: [String]
      }
      var metrics = Metrics(dependencies: [])
      let package = Package(
        name: "App",
        targets: [.target(name: "App")]
      )
      metrics.dependencies.append("sample")
      """
    )

    #expect(manifest.targets.values?.map(\.name) == ["App"])
  }

  @Test("Parser applies mutation from active compilation branch")
  func appliesActiveCompilationBranchMutation() {
    let manifest = PackageManifest(
      source: """
      let package = Package(name: "App", targets: [])
      #if os(macOS)
      package.targets.append(.target(name: "MacApp"))
      #else
      package.targets.append(.target(name: "OtherApp"))
      #endif
      """
    )

    #if os(macOS)
      #expect(manifest.targets.values?.map(\.name) == ["MacApp"])
    #else
      #expect(manifest.targets.values?.map(\.name) == ["OtherApp"])
    #endif
  }

  @Test("A helper that changes the package makes mutable fields incomplete")
  func detectsCapturingHelperCalls() {
    let manifest = PackageManifest(
      source: """
      func configure() {
        package.targets.append(.target(name: "Feature"))
      }
      let package = Package(
        name: "App",
        targets: [.target(name: "App")]
      )
      configure()
      """
    )

    #expect(!manifest.targets.isComplete)
    #expect(!manifest.products.isComplete)
    #expect(!manifest.dependencies.isComplete)
  }

  @Test("Static members outside PackageDescription are unresolved")
  func rejectsUnrelatedStaticMembers() {
    let manifest = PackageManifest(
      source: """
      let standard = Config.standard
      let package = Package(
        name: "App",
        cLanguageStandard: standard,
        targets: []
      )
      """
    )

    #expect(manifest.cLanguageStandard == nil)
    #expect(!manifest.isComplete)
  }

  @Test("Package and target calls on other types are unresolved")
  func rejectsCallsOnOtherTypes() {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        dependencies: [Registry.package(id: "example.app")],
        targets: [Factory.target(name: "App")]
      )
      """
    )

    #expect(manifest.dependencies.knownValues.isEmpty)
    #expect(!manifest.dependencies.isComplete)
    #expect(manifest.targets.knownValues.isEmpty)
    #expect(!manifest.targets.isComplete)
  }

  @Test("Filtered manifest lists are incomplete")
  func preservesUncertaintyInLookups() {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        products: [
          .library(name: "App", targets: productTargets),
        ],
        dependencies: makeDependencies(),
        targets: makeTargets()
      )
      """
    )

    #expect(!manifest.targets(named: "Core").isComplete)
    #expect(!manifest.dependencies(named: "Example").isComplete)
    #expect(
      !manifest.products(
        containing: PackageManifest.Target(name: "Core")
      ).isComplete
    )
  }
}
