import BylawsSemantics
import Foundation
import Testing

@Suite("Package manifest target features")
struct PackageManifestTargetFeatureTests {
  @Test(
    "Each target dependency includes its kind, package, aliases and conditions"
  )
  func readsTypedTargetDependencies() throws {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        targets: [
          .target(name: "Core"),
          .target(
            name: "Feature",
            dependencies: [
              "Core",
              .target(
                name: "PlatformCore",
                condition: .when(platforms: [.macOS])
              ),
              .product(
                name: "Algorithms",
                package: "swift-algorithms",
                moduleAliases: ["Algorithms": "AppAlgorithms"],
                condition: .when(traits: ["Algorithms"])
              ),
            ]
          ),
        ]
      )
      """
    )

    let feature = try #require(
      manifest.targets(named: "Feature").values?.first
    )
    let dependencies = try #require(feature.dependencies.values)
    try #require(dependencies.count == 3)
    #expect(dependencies.map(\.kind) == [.byName, .target, .product])
    #expect(dependencies[1].condition?.platforms == ["macOS"])
    #expect(dependencies[2].packageName == "swift-algorithms")
    #expect(dependencies[2].moduleAliases == [
      "Algorithms": "AppAlgorithms",
    ])
    #expect(dependencies[2].condition?.traitNames == ["Algorithms"])
  }

  @Test("Parser reads target paths, resources, settings and plugins")
  func readsTargetConfiguration() throws {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        targets: [
          .target(
            name: "Core",
            path: "Modules/Core",
            exclude: ["Legacy"],
            sources: ["Core.swift"],
            resources: [
              .process("Assets", localization: .default),
              .copy("Config.json"),
              .embedInCode("Schema.json"),
            ],
            publicHeadersPath: "Headers",
            packageAccess: false,
            cSettings: [
              .define("C_FEATURE", to: "1"),
              .headerSearchPath("Includes"),
              .unsafeFlags(["-fmodules"]),
            ],
            cxxSettings: [
              .enableWarning("unused-variable"),
              .disableWarning("deprecated-declarations"),
            ],
            swiftSettings: [
              .define("SWIFT_FEATURE"),
              .enableUpcomingFeature("ExistentialAny"),
              .enableExperimentalFeature("Example"),
              .strictMemorySafety(.when(platforms: [.macOS])),
              .interoperabilityMode(.Cxx),
              .swiftLanguageMode(.v6),
              .treatAllWarnings(as: .error),
              .treatWarning("Deprecated", as: .warning),
              .defaultIsolation(MainActor.self),
            ],
            linkerSettings: [
              .linkedLibrary("sqlite3"),
              .linkedFramework("Foundation"),
            ],
            plugins: [
              .plugin(name: "FormatPlugin", package: "format-package"),
            ]
          ),
        ]
      )
      """
    )

    let target = try #require(manifest.targets.values?.first)
    #expect(target.path == "Modules/Core")
    #expect(target.excludedPaths.values == ["Legacy"])
    #expect(target.sources == .explicit(.init(knownValues: ["Core.swift"])))
    #expect(target.resources.values?.map(\.rule) == [
      .process,
      .copy,
      .embedInCode,
    ])
    #expect(target.publicHeadersPath == "Headers")
    #expect(!target.packageAccess)
    #expect(target.buildSettings.values?.count == 16)
    #expect(target.buildSettings.knownValues.contains { $0.usesUnsafeFlags })
    let strictMemorySafety = try #require(
      target.buildSettings.knownValues.first {
        $0.value == .strictMemorySafety
      }
    )
    #expect(strictMemorySafety.condition?.platforms == ["macOS"])
    #expect(
      target.buildSettings.knownValues.contains {
        $0.value == .defaultIsolation(.mainActor)
      }
    )
    #expect(target.plugins.values == [
      .init(name: "FormatPlugin", packageName: "format-package"),
    ])
  }

  @Test("A product plugin usage is unresolved")
  func rejectsProductPluginUsages() throws {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        targets: [
          .target(
            name: "App",
            plugins: [.product(name: "Tool", package: "tools")]
          ),
        ]
      )
      """
    )

    let target = try #require(manifest.targets.values?.first)
    #expect(target.plugins.knownValues.isEmpty)
    #expect(!target.plugins.isComplete)
    #expect(!target.isComplete)
  }

  @Test("Parser reads system, binary and plugin target details")
  func readsSpecialTargetDetails() throws {
    let manifest = PackageManifest(
      source: """
      let previewPort = 8080
      let servicePorts = 8000..<8010
      let package = Package(
        name: "App",
        targets: [
          .systemLibrary(
            name: "CLib",
            pkgConfig: "libexample",
            providers: [.brew(["example"]), .apt(["libexample-dev"])]
          ),
          .binaryTarget(
            name: "RemoteSDK",
            url: "https://example.com/sdk.zip",
            checksum: "abc123"
          ),
          .plugin(
            name: "CommandPlugin",
            capability: .command(
              intent: .documentationGeneration(),
              permissions: [
                .writeToPackageDirectory(reason: "Updates generated files."),
                .allowNetworkConnections(
                  scope: .local(ports: [previewPort]),
                  reason: "Connects to the preview server."
                ),
                .allowNetworkConnections(
                  scope: .all(ports: servicePorts),
                  reason: "Connects to test services."
                ),
              ]
            )
          ),
        ]
      )
      """
    )

    let system = try #require(
      manifest.targets(named: "CLib").values?.first
    )
    #expect(system.pkgConfig == "libexample")
    #expect(system.providers.values?.map(\.kind) == [.brew, .apt])
    let binary = try #require(
      manifest.targets(named: "RemoteSDK").values?.first
    )
    #expect(
      binary.binarySource
        == .remote(url: "https://example.com/sdk.zip", checksum: "abc123")
    )
    let plugin = try #require(
      manifest.targets(named: "CommandPlugin").values?.first
    )
    let capability = try #require(plugin.pluginCapability)
    guard case let .command(intent, permissions) = capability
    else {
      Issue.record("Expected a command plugin")
      return
    }
    try #require(permissions.count == 3)
    #expect(intent == .documentationGeneration)
    #expect(
      permissions[1]
        == .allowNetworkConnections(
          scope: .local(ports: .values([8080])),
          reason: "Connects to the preview server."
        )
    )
    #expect(
      permissions.last
        == .allowNetworkConnections(
          scope: .all(ports: .range(from: 8000, upTo: 8010)),
          reason: "Connects to test services."
        )
    )
  }

  @Test("A build setting accepts only values supported by its tool")
  func rejectsInvalidToolAndValuePairs() {
    #expect(
      PackageManifest.Target.Setting(
        tool: .linker,
        value: .strictMemorySafety
      ) == nil
    )
    #expect(
      PackageManifest.Target.Setting(
        tool: .swift,
        value: .headerSearchPath("Includes")
      ) == nil
    )
  }

  @Test("Nil target options use default values")
  func readsNilTargetCollectionsAsEmpty() throws {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        targets: [
          .target(
            name: "App",
            sources: nil,
            resources: nil,
            cSettings: nil,
            cxxSettings: nil,
            swiftSettings: nil,
            linkerSettings: nil,
            plugins: nil
          ),
          .systemLibrary(name: "System", providers: nil),
        ]
      )
      """
    )

    let app = try #require(manifest.targets(named: "App").values?.first)
    #expect(app.sources == .automatic)
    #expect(app.resources.values?.isEmpty == true)
    #expect(app.buildSettings.values?.isEmpty == true)
    #expect(app.plugins.values?.isEmpty == true)
    let system = try #require(
      manifest.targets(named: "System").values?.first
    )
    #expect(system.providers.values?.isEmpty == true)
  }

  @Test("Decoder rejects build setting with invalid tool")
  func validatesDecodedBuildSettings() throws {
    let setting = try #require(
      PackageManifest.Target.Setting(
        tool: .swift,
        value: .strictMemorySafety
      )
    )
    let encoded = try JSONEncoder().encode(setting)
    let written = try #require(String(data: encoded, encoding: .utf8))
      .replacing("\"swift\"", with: "\"linker\"")

    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(
        PackageManifest.Target.Setting.self,
        from: Data(written.utf8)
      )
    }
  }
}
