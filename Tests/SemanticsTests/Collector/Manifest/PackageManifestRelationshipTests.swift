import BylawsSemantics
import Testing

@Suite("Package manifest target relationships")
struct PackageManifestRelationshipTests {
  @Test("Test target search follows direct and transitive dependencies")
  func findsDirectAndTransitiveTestTargets() throws {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        products: [.library(name: "App", targets: ["Feature"])],
        targets: [
          .target(name: "Core"),
          .target(name: "Feature", dependencies: [.target(name: "Core")]),
          .testTarget(
            name: "Checks",
            dependencies: [.byName(name: "Feature")]
          ),
          .target(name: "TestSupport"),
        ]
      )
      """
    )

    let core = try #require(manifest.targets(named: "Core").values?
      .first)
    let feature = try #require(
      manifest.targets(named: "Feature").values?.first
    )
    #expect(
      manifest.testTargets(dependingDirectlyOn: feature).values?
        .map(\.name)
        == ["Checks"]
    )
    #expect(
      manifest.testTargets(dependingDirectlyOn: core).values?.isEmpty
        == true
    )
    #expect(
      manifest.testTargets(dependingOn: core).values?.map(\.name)
        == ["Checks"]
    )
    #expect(manifest.targets().values?.map(\.name) == [
      "Feature",
      "Core",
    ])
  }

  @Test("Product dependency creates no local target edge")
  func excludesProductDependenciesFromLocalEdges() throws {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        targets: [
          .target(name: "Shared"),
          .testTarget(
            name: "Checks",
            dependencies: [
              .product(name: "Shared", package: "external")
            ]
          ),
        ]
      )
      """
    )

    let shared = try #require(
      manifest.targets(named: "Shared").values?.first
    )
    #expect(
      manifest.testTargets(dependingOn: shared).values?.isEmpty == true
    )
  }

  @Test("Test target search includes conditional edges when requested")
  func handlesConditionalTestDependencies() throws {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        targets: [
          .target(name: "Core"),
          .testTarget(
            name: "Checks",
            dependencies: [
              .target(name: "Core", condition: .when(platforms: [.macOS]))
            ]
          ),
        ]
      )
      """
    )

    let core = try #require(manifest.targets(named: "Core").values?
      .first)
    #expect(
      manifest.testTargets(dependingOn: core).values?.isEmpty == true
    )
    #expect(
      manifest.testTargets(
        dependingOn: core,
        includingConditionalDependencies: true
      ).conditionalValues.map(\.name) == ["Checks"]
    )
  }

  @Test("A known path overrides a conditional path")
  func prefersKnownDependencyPaths() throws {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        targets: [
          .target(name: "Shared", dependencies: ["Core"]),
          .target(name: "Core"),
          .target(name: "Bridge", dependencies: ["Shared"]),
          .target(
            name: "Feature",
            dependencies: [
              .target(
                name: "Shared",
                condition: .when(platforms: [.macOS])
              ),
              "Bridge",
            ]
          ),
        ]
      )
      """
    )

    let feature = try #require(
      manifest.targets(named: "Feature").values?.first
    )
    let dependencies = manifest.transitiveTargetDependencies(
      of: feature,
      includingConditionalDependencies: true
    )
    #expect(dependencies.knownValues.map(\.name) == [
      "Bridge",
      "Shared",
      "Core",
    ])
    #expect(dependencies.conditionalValues.isEmpty)
  }

  @Test("Direct dependency search includes conditional values when requested")
  func handlesConditionallyAppendedDependencies() throws {
    let manifest = PackageManifest(
      targets: [
        .init(name: "Core"),
        .init(
          name: "Checks",
          dependencies: .init(
            conditionalValues: [.init(name: "Core")]
          ),
          kind: .test
        ),
      ]
    )

    let checks = try #require(
      manifest.targets.knownValues.first { $0.name == "Checks" }
    )
    #expect(
      manifest.directTargetDependencies(of: checks).values?.isEmpty == true
    )
    #expect(
      manifest.directTargetDependencies(
        of: checks,
        includingConditionalDependencies: true
      ).conditionalValues.map(\.name) == ["Core"]
    )
  }

  @Test("Graph queries mark conditional targets as conditional")
  func preservesConditionalDeclarations() throws {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        products: [],
        targets: [.target(name: "Core")]
      )
      if enabled {
        package.targets.append(
          .target(name: "Feature", dependencies: ["Core"])
        )
        package.products.append(
          .library(name: "Feature", targets: ["Feature"])
        )
      }
      """
    )

    let feature = try #require(
      manifest.targets.conditionalValues.first { $0.name == "Feature" }
    )
    #expect(
      manifest.directTargetDependencies(of: feature).knownValues.map(\.name)
        == ["Core"]
    )
    #expect(manifest.targets().knownValues.isEmpty)
    #expect(
      Set(manifest.targets().conditionalValues.map(\.name))
        == ["Feature", "Core"]
    )
  }

  @Test("Local graph is complete with an external by-name dependency")
  func handlesExternalByNameDependencies() throws {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        targets: [
          .target(name: "Core"),
          .testTarget(name: "Checks", dependencies: ["Core", "External"]),
        ]
      )
      """
    )

    let core = try #require(manifest.targets(named: "Core").values?
      .first)
    #expect(
      manifest.testTargets(dependingOn: core).values?.map(\.name)
        == ["Checks"]
    )
  }

  @Test("Dependency queries stop at a cycle")
  func handlesDependencyCycles() throws {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        targets: [
          .target(name: "First", dependencies: ["Second"]),
          .target(name: "Second", dependencies: ["First"]),
          .testTarget(name: "Checks", dependencies: ["First"]),
        ]
      )
      """
    )

    let first = try #require(
      manifest.targets(named: "First").values?.first
    )
    let second = try #require(
      manifest.targets(named: "Second").values?.first
    )
    #expect(
      manifest.transitiveTargetDependencies(of: first).values?.map(\.name)
        == ["Second"]
    )
    #expect(
      manifest.testTargets(dependingOn: second).values?.map(\.name)
        == ["Checks"]
    )
  }

  @Test("Transitive queries report unresolved reachable dependencies")
  func scopesUnresolvedDependenciesToReachableTargets() throws {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        targets: [
          .target(name: "App", dependencies: ["Core"]),
          .target(
            name: "Core",
            dependencies: [.target(name: "Missing")]
          ),
          .target(
            name: "Unrelated",
            dependencies: [.target(name: "OtherMissing")]
          ),
        ]
      )
      """
    )

    let app = try #require(
      manifest.targets(named: "App").values?.first
    )
    let unresolved = manifest.transitiveTargetDependencies(of: app)
      .unresolvedValues.map(\.expression)
    #expect(unresolved.contains("missing local target Missing"))
    #expect(!unresolved.contains("missing local target OtherMissing"))
  }

  @Test("Graph reports each unresolved package value once")
  func doesNotDuplicateUnresolvedPackageValues() {
    let unresolvedTargetList = PackageManifest.UnresolvedValue(
      field: "targets",
      expression: "generated targets"
    )
    let core = PackageManifest.Target(
      name: "Core",
      dependencies: .init(knownValues: [
        .init(name: "Missing", kind: .target),
      ])
    )
    let app = PackageManifest.Target(
      name: "App",
      dependencies: .init(knownValues: [.init(name: "Core")])
    )
    let manifest = PackageManifest(
      targets: ManifestList(
        knownValues: [app, core],
        unresolvedValues: [unresolvedTargetList]
      )
    )

    let unresolved = manifest.transitiveTargetDependencies(of: app)
      .unresolvedValues
    #expect(unresolved == [
      unresolvedTargetList,
      PackageManifest.UnresolvedValue(
        field: "targets.Core.dependencies",
        expression: "missing local target Missing"
      ),
    ])
  }

  @Test("Executable target appears without explicit product")
  func includesImplicitExecutableProducts() {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "Tool",
        targets: [
          .target(name: "Core"),
          .executableTarget(name: "Tool", dependencies: ["Core"]),
        ]
      )
      """
    )

    #expect(manifest.targets().values?.map(\.name) == [
      "Tool",
      "Core",
    ])
  }

  @Test(
    "Large target graph resolves each relationship",
    .timeLimit(.minutes(1))
  )
  func resolvesLargeGraph() throws {
    let targetCount = 10000
    var targets = (0..<targetCount).map { index in
      let dependencies: ManifestList<PackageManifest.Target.Dependency> =
        if index + 1 < targetCount {
          .init(knownValues: [.init(name: "Target\(index + 1)")])
        } else {
          .init()
        }
      return PackageManifest.Target(
        name: "Target\(index)",
        dependencies: dependencies
      )
    }
    targets.append(
      PackageManifest.Target(
        name: "Checks",
        dependencies: .init(knownValues: [.init(name: "Target0")]),
        kind: .test
      )
    )
    let manifest = PackageManifest(
      products: .init(knownValues: [
        .init(
          name: "App",
          kind: .library(linkage: .automatic),
          targetNames: ["Target0"]
        ),
      ]),
      targets: .init(knownValues: targets)
    )

    let root = try #require(targets.first)
    let leaf = targets[targetCount - 1]
    #expect(
      manifest.transitiveTargetDependencies(of: root).knownValues.count
        == targetCount - 1
    )
    #expect(
      manifest.testTargets(dependingOn: leaf).knownValues.map(\.name)
        == ["Checks"]
    )
    #expect(manifest.targets().knownValues.count == targetCount)
  }
}
