import BylawsSemantics
import Testing

@Suite("Package manifest reading")
struct PackageManifestTests {
  @Test("A hyphenated target has an importable module name")
  func hyphenatedTargetModuleName() {
    let target = PackageManifest.Target(name: "bylaws-cli")
    #expect(target.moduleName == "bylaws_cli")
  }

  @Test(
    "Every character a C99 identifier rejects becomes an underscore",
    arguments: [
      ("bylaws-cli", "bylaws_cli"),
      ("Foo+Bar", "Foo_Bar"),
      ("my.tool", "my_tool"),
      ("2fast", "_2fast"),
    ]
  )
  func mangledModuleName(name: String, module: String) {
    #expect(PackageManifest.Target(name: name).moduleName == module)
  }

  @Test(
    "Parser reads package dependency requirements",
    arguments: [
      ManifestDependencyCase(
        testDescription: "Exact URL requirement",
        declaration:
        """
        .package(
          url: "https://github.com/apple/swift-crypto.git",
          exact: "4.5.1"
        )
        """,
        dependency: PackageManifest.Dependency(
          name: "swift-crypto",
          source: .url("https://github.com/apple/swift-crypto.git"),
          requirement: .exact(.init(4, 5, 1))
        )
      ),
      ManifestDependencyCase(
        testDescription: "Closed version range",
        declaration:
        ".package(url: \"https://example.com/closed.git\", \"1.0.0\"...\"1.4.0\")",
        dependency: PackageManifest.Dependency(
          name: "closed",
          source: .url("https://example.com/closed.git"),
          requirement: .closedRange(
            from: .init(1, 0, 0),
            through: .init(1, 4, 0)
          )
        )
      ),
      ManifestDependencyCase(
        testDescription: "Half-open version range",
        declaration:
        """
        .package(
          url: "https://github.com/swiftlang/swift-syntax.git",
          "602.0.0"..<"604.0.0"
        )
        """,
        dependency: PackageManifest.Dependency(
          name: "swift-syntax",
          source: .url("https://github.com/swiftlang/swift-syntax.git"),
          requirement: .range(from: .init(602, 0, 0), upTo: .init(604, 0, 0))
        )
      ),
      ManifestDependencyCase(
        testDescription: "Named next-major requirement",
        declaration:
        """
        .package(
          name: "ArgumentParser",
          url: "https://github.com/apple/swift-argument-parser.git",
          from: "1.8.2"
        )
        """,
        dependency: PackageManifest.Dependency(
          name: "ArgumentParser",
          source: .url(
            "https://github.com/apple/swift-argument-parser.git"
          ),
          requirement: .upToNextMajor(from: .init(1, 8, 2))
        )
      ),
      ManifestDependencyCase(
        testDescription: "Next-minor requirement",
        declaration:
        """
        .package(
          url: "https://example.com/minor.git",
          .upToNextMinor(from: "2.3.0")
        )
        """,
        dependency: PackageManifest.Dependency(
          name: "minor",
          source: .url("https://example.com/minor.git"),
          requirement: .upToNextMinor(from: .init(2, 3, 0))
        )
      ),
      ManifestDependencyCase(
        testDescription: "Explicit exact requirement",
        declaration:
        ".package(url: \"https://example.com/exact.git\", .exact(\"3.0.0\"))",
        dependency: PackageManifest.Dependency(
          name: "exact",
          source: .url("https://example.com/exact.git"),
          requirement: .exact(.init(3, 0, 0))
        )
      ),
      ManifestDependencyCase(
        testDescription: "Branch requirement",
        declaration:
        ".package(url: \"https://example.com/branch.git\", branch: \"main\")",
        dependency: PackageManifest.Dependency(
          name: "branch",
          source: .url("https://example.com/branch.git"),
          requirement: .branch("main")
        )
      ),
      ManifestDependencyCase(
        testDescription: "Revision requirement",
        declaration:
        ".package(url: \"https://example.com/revision.git\", revision: \"abc\")",
        dependency: PackageManifest.Dependency(
          name: "revision",
          source: .url("https://example.com/revision.git"),
          requirement: .revision("abc")
        )
      ),
      ManifestDependencyCase(
        testDescription: "Local path requirement",
        declaration: ".package(path: \"../LocalTools\")",
        dependency: PackageManifest.Dependency(
          name: "LocalTools",
          source: .path("../LocalTools"),
          requirement: .local
        )
      ),
      ManifestDependencyCase(
        testDescription: "Registry requirement",
        declaration:
        ".package(id: \"example.registry-package\", exact: \"1.0.0\")",
        dependency: PackageManifest.Dependency(
          name: "example.registry-package",
          source: .registryIdentity("example.registry-package"),
          requirement: .exact(.init(1, 0, 0))
        )
      ),
    ]
  )
  func readsPackageDependency(_ testCase: ManifestDependencyCase) {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        dependencies: [\(testCase.declaration)],
        targets: []
      )
      """
    )
    #expect(manifest.dependencies.values == [testCase.dependency])
  }

  @Test("A semantic version has numeric, prerelease and build parts")
  func readsSemanticVersionComponents() throws {
    let written = "12.3.4-beta.2+build.9"
    let version = try #require(PackageManifest.Version(written))
    #expect(version.major == 12)
    #expect(version.minor == 3)
    #expect(version.patch == 4)
    #expect(version.prereleaseIdentifiers == ["beta", "2"])
    #expect(version.buildMetadataIdentifiers == ["build", "9"])
    #expect(version.description == "12.3.4-beta.2+build.9")
  }

  @Test(
    "Invalid semantic versions are rejected",
    arguments: [
      "1",
      "1.2",
      "1.2.3.4",
      "01.2.3",
      "1.02.3",
      "1.2.03",
      "1.2.3-",
      "1.2.3-alpha..1",
      "1.2.3-01",
      "1.2.3+",
      "1.2.3+build..1",
      "1.2.3+build!",
    ]
  )
  func rejectsInvalidSemanticVersion(_ written: String) {
    #expect(PackageManifest.Version(written) == nil)
  }

  @Test("Semantic versions follow prerelease precedence")
  func comparesSemanticVersions() throws {
    let versions = try [
      "1.0.0-alpha",
      "1.0.0-alpha.1",
      "1.0.0-alpha.beta",
      "1.0.0-beta",
      "1.0.0-beta.2",
      "1.0.0-beta.11",
      "1.0.0-rc.1",
      "1.0.0",
    ].map { try #require(PackageManifest.Version($0)) }
    #expect(versions.sorted() == versions)
    #expect(
      PackageManifest.Version("1.0.0+one")
        == PackageManifest.Version("1.0.0+two")
    )
  }

  @Test("A version requirement has a minimum version")
  func readsRequirementVersion() throws {
    let requirement = PackageManifest.Dependency.Requirement.range(
      from: .init(602, 1, 2),
      upTo: .init(604, 0, 0)
    )
    let version = try #require(requirement.minimumVersion)
    let majorVersion = try #require(requirement.majorVersion)
    #expect(version >= PackageManifest.Version(602, 0, 0))
    #expect(majorVersion > 600)
    #expect(
      PackageManifest.Dependency.Requirement.branch("main").minimumVersion
        == nil
    )
  }

  @Test("An unresolved target list is incomplete")
  func preservesUnresolvedTargets() {
    let manifest = PackageManifest(
      source: """
      let package = Package(name: "App", targets: allTargets)
      """
    )
    #expect(manifest.targets.knownValues.isEmpty)
    #expect(!manifest.targets.isComplete)
  }

  @Test("An unresolved dependency list is incomplete")
  func preservesUnresolvedPackageDependencies() {
    let manifest = PackageManifest(
      source: """
      let package = Package(
        name: "App",
        dependencies: allDependencies,
        targets: []
      )
      """
    )
    #expect(manifest.dependencies.knownValues.isEmpty)
    #expect(!manifest.dependencies.isComplete)
  }
}

struct ManifestDependencyCase:
  Codable,
  Sendable,
  CustomTestStringConvertible
{
  let testDescription: String
  let declaration: String
  let dependency: PackageManifest.Dependency
}
