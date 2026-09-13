import BylawsSemantics
import Testing

@Suite("Package manifest target reading")
struct PackageManifestTargetTests {
  @Test("Parser reads target names, kinds and dependencies")
  func readsTargets() throws {
    let manifest = PackageManifest(
      source: """
      // swift-tools-version: 6.0
      import PackageDescription

      let package = Package(
        name: "App",
        targets: [
          .target(name: "Domain"),
          .target(
            name: "Feature",
            dependencies: [
              "Domain",
              .product(name: "Algorithms", package: "swift-algorithms"),
            ]
          ),
          .testTarget(name: "FeatureTests", dependencies: ["Feature"]),
        ]
      )
      """
    )

    let targets = try #require(manifest.targets.values)
    #expect(targets.map(\.name) == [
      "Domain",
      "Feature",
      "FeatureTests",
    ])

    let feature = try #require(targets.first { $0.name == "Feature" })
    #expect(feature.dependencyNames.values == ["Domain", "Algorithms"])
    #expect(feature.kind == .regular)
    #expect(feature.sourceDirectory == "Sources/Feature")
    #expect(!feature.isTest)

    let tests = try #require(
      targets.first { $0.name == "FeatureTests" }
    )
    #expect(tests.kind == .test)
    #expect(tests.isTest)
    #expect(tests.sourceDirectory == "Tests/FeatureTests")
  }

  @Test("A plugin target uses the Plugins source directory")
  func pluginTargetRootsAtPlugins() throws {
    let manifest = PackageManifest(
      source: """
      // swift-tools-version: 6.0
      import PackageDescription

      let package = Package(
        name: "App",
        targets: [
          .executableTarget(name: "tool"),
          .plugin(
            name: "ToolPlugin",
            capability: .command(
              intent: .custom(verb: "tool", description: "Runs the tool.")
            ),
            dependencies: [.target(name: "tool")]
          ),
        ]
      )
      """
    )

    let targets = try #require(manifest.targets.values)
    let plugin = try #require(targets.first { $0.name == "ToolPlugin" })
    #expect(plugin.kind == .plugin)
    #expect(plugin.isPlugin)
    #expect(!plugin.isTest)
    #expect(plugin.sourceDirectory == "Plugins/ToolPlugin")
    #expect(plugin.dependencyNames.values == ["tool"])

    let tool = try #require(targets.first { $0.name == "tool" })
    #expect(tool.kind == .executable)
    #expect(!tool.isPlugin)
    #expect(tool.sourceDirectory == "Sources/tool")
  }

  @Test("Every supported target form has one kind")
  func readsEveryTargetKind() {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        targets: [
          .target(name: "Regular"),
          .executableTarget(name: "Executable"),
          .macro(name: "Macro"),
          .testTarget(name: "Tests"),
          .systemLibrary(name: "System"),
          .binaryTarget(name: "Binary", path: "Binary.xcframework"),
          .plugin(name: "Plugin", capability: .buildTool()),
        ]
      )
      """
    )

    #expect(manifest.targets.values?.map(\.kind) == [
      .regular,
      .executable,
      .macro,
      .test,
      .systemLibrary,
      .binary,
      .plugin,
    ])
  }

  @Test(
    "Parser returns a module name for every dependency form",
    arguments: [
      ("\"Core\"", ["Core"]),
      (".byName(\"Core\")", ["Core"]),
      (".target(name: \"Core\")", ["Core"]),
      (".product(name: \"Core\", package: \"core\")", ["Core"]),
    ]
  )
  func readsDependencyForms(written: String, names: [String]) throws {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        targets: [.target(name: "App", dependencies: [\(written)])]
      )
      """
    )
    let target = try #require(manifest.targets.values?.first)
    #expect(target.dependencyNames.values == names)
  }

  @Test("A .target dependency does not declare a target")
  func dependencyFormIsNotATarget() throws {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        targets: [
          .target(name: "Base"),
          .target(name: "App", dependencies: [.target(name: "Base")]),
        ]
      )
      """
    )
    let targets = try #require(manifest.targets.values)
    #expect(targets.map(\.name) == ["Base", "App"])
    let app = try #require(targets.last)
    #expect(app.dependencyNames.values == ["Base"])
  }

  @Test("Parser skips a commented-out dependency")
  func skipsComments() throws {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        targets: [
          .target(name: "App", dependencies: [
            // "Legacy",
            "Utils",
          ]),
        ]
      )
      """
    )
    let app = try #require(manifest.targets.values?.first)
    #expect(app.dependencyNames.values == ["Utils"])
  }

  @Test("Parser reads dependencies after computed package name")
  func readsAfterComputedValue() throws {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        targets: [
          .target(name: "App", dependencies: [
            .product(name: "Core", package: corePackageName),
            "Utils",
          ]),
        ]
      )
      """
    )
    let app = try #require(manifest.targets.values?.first)
    #expect(app.dependencyNames.values == ["Core", "Utils"])
  }

  @Test("Target and dependency names decode Swift string literals")
  func decodesStringLiterals() {
    let manifest = PackageManifest(
      source: #"""
      let package = Package(
        name: "App",
        targets: [
          .target(name: "Feature\u{20}Core"),
          .target(name: "App", dependencies: [#"Feature Core"#]),
        ]
      )
      """#
    )

    #expect(manifest.targets.values?.map(\.name) == [
      "Feature Core",
      "App",
    ])
    #expect(
      manifest.targets.values?.last?.dependencyNames.values
        == ["Feature Core"]
    )
  }

  @Test(
    "Parser removes leading ./ and trailing / from target paths",
    arguments: [
      // Path, directory.
      ("Vendor/Legacy", "Vendor/Legacy"),
      ("Sources/Other/", "Sources/Other"),
      ("./Sources/Other", "Sources/Other"),
      (".", ""),
    ]
  )
  func normalisesPaths(written: String, directory: String) throws {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        targets: [.target(name: "App", path: "\(written)")]
      )
      """
    )
    let target = try #require(manifest.targets.values?.first)
    #expect(target.sourceDirectory == directory)
  }
}
