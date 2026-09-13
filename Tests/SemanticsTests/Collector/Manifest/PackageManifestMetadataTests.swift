import BylawsSemantics
import Testing

@Suite("Package manifest metadata")
struct PackageManifestMetadataTests {
  @Test("Parser reads package metadata fields")
  func readsPackageMetadata() throws {
    let manifest = PackageManifest(
      source: """
      // swift-tools-version: 6.2
      let package = Package(
        name: "App",
        defaultLocalization: "en",
        platforms: [
          .macOS(.v10_15),
          .iOS("13.1"),
          .custom("wasi", versionString: "1.0"),
        ],
        products: [
          .library(name: "App", type: .static, targets: ["App"]),
          .library(name: "Support", targets: ["Support"]),
          .executable(name: "Tool", targets: ["Tool"]),
          .plugin(name: "FormatPlugin", targets: ["FormatPlugin"]),
        ],
        traits: [
          .trait(
            name: "Feature",
            description: "Enables the feature.",
            enabledTraits: ["Foundation"]
          ),
          .default(enabledTraits: ["Feature"]),
        ],
        targets: [],
        swiftLanguageModes: [.v5, .v6],
        cLanguageStandard: .c17,
        cxxLanguageStandard: .cxx20
      )
      """
    )

    #expect(manifest.name == "App")
    #expect(manifest.toolsVersion == PackageManifest.ToolsVersion(6, 2))
    #expect(manifest.defaultLocalization == "en")
    #expect(manifest.platforms.values == [
      .init(name: "macOS", minimumVersion: .init(10, 15)),
      .init(name: "iOS", minimumVersion: .init(13, 1)),
      .init(name: "wasi", minimumVersion: .init(1, 0)),
    ])
    #expect(manifest.products.values?.map(\.kind) == [
      .library(linkage: .static),
      .library(linkage: .automatic),
      .executable,
      .plugin,
    ])
    let trait = try #require(manifest.traits.values?.first)
    #expect(trait.name == "Feature")
    #expect(trait.enabledTraitNames == ["Foundation"])
    #expect(manifest.defaultTraitNames.values == ["Feature"])
    #expect(manifest.swiftLanguageModes.values == ["v5", "v6"])
    #expect(manifest.cLanguageStandard == "c17")
    #expect(manifest.cxxLanguageStandard == "cxx20")
  }

  @Test("Default dependency traits differ from an empty trait list")
  func readsDependencyTraits() throws {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        dependencies: [
          .package(url: "https://example.com/defaults.git", exact: "1.0.0"),
          .package(
            url: "https://example.com/none.git",
            exact: "1.0.0",
            traits: []
          ),
          .package(
            url: "https://example.com/named.git",
            exact: "1.0.0",
            traits: [
              .defaults,
              "Feature",
              .trait(name: "Logging", condition: .when(traits: ["Host"])),
            ]
          ),
        ],
        targets: []
      )
      """
    )

    let dependencies = try #require(manifest.dependencies.values)
    try #require(dependencies.count == 3)
    #expect(dependencies[0].traits.values == [.defaults])
    #expect(dependencies[1].traits.values == [])
    #expect(dependencies[2].traits.values?.map(\.kind) == [
      .defaults,
      .named("Feature"),
      .named("Logging"),
    ])
    #expect(
      dependencies[2].traits.knownValues.last?.condition?.traitNames
        == ["Host"]
    )
  }

  @Test("Tools and platform versions compare numeric parts")
  func comparesManifestVersions() throws {
    let tools = try #require(PackageManifest.ToolsVersion("6.10"))
    #expect(tools > PackageManifest.ToolsVersion(6, 2))
    let platform = try #require(PackageManifest.PlatformVersion("14"))
    #expect(platform == PackageManifest.PlatformVersion(14, 0))
    let older = try #require(PackageManifest.PlatformVersion("13.4"))
    #expect(older < platform)
    let overflowing = "999999999999999999999.2"
    #expect(PackageManifest.ToolsVersion(overflowing) == nil)
  }

  @Test("Parser reads legacy Swift language versions")
  func readsSwiftLanguageVersions() {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        targets: [],
        swiftLanguageVersions: [.v5, 6]
      )
      """
    )

    #expect(manifest.swiftLanguageModes.values == ["v5", "6"])
  }

  @Test("Trait values can come from an immutable Set")
  func resolvesTraitSets() throws {
    let manifest = PackageManifest(
      source: """
      let enabled = Set(["Foundation", "Logging"])
      let package = Package(
        name: "App",
        traits: [
          "Basic",
          .trait(name: "Feature", enabledTraits: enabled),
          .default(enabledTraits: Set(["Feature"])),
        ],
        targets: []
      )
      """
    )

    let traits = try #require(manifest.traits.values)
    try #require(traits.count == 2)
    #expect(traits.map(\.name) == ["Basic", "Feature"])
    let trait = traits[1]
    #expect(trait.enabledTraitNames == ["Foundation", "Logging"])
    #expect(manifest.defaultTraitNames.values == ["Feature"])
  }
}
