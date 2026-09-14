import BylawsCore
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Codebase language settings")
struct CodebaseLanguageModeTests {
  @Test("Manifest queries use tools language mode")
  func manifestSyntax() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": """
      // swift-tools-version: 5.9
      @available (swift, obsoleted: 1.0)
      struct Legacy {}
      let package = Package(name: "App", targets: [.target(name: "App")])
      """,
      "Sources/App/App.swift": "struct App {}",
    ])
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"]
    )

    #expect(try await codebase.packageManifest.name == "App")
  }

  @Test("Explicit modes use separate in-memory entries")
  func explicitModes() async throws {
    let root = Codebase.Root.sources([
      "Legacy.swift": "@available (swift, obsoleted: 1.0)\nstruct Legacy {}",
    ])
    let swift5 = Codebase(root: root, swiftLanguageMode: .v5)
    let swift6 = Codebase(root: root, swiftLanguageMode: .v6)

    #expect(try await swift5.structs.count == 1)
    await #expect(throws: CodebaseError.self) { try await swift6.prepare() }
    #expect(try await swift5.structs.count == 1)
  }

  @Test("Package tools version supplies default mode", arguments: [
    ("4.2", SwiftLanguageMode.v4),
    ("5.9", .v5),
    ("6.0", .v6),
  ])
  func packageDefault(
    version: String,
    expected: SwiftLanguageMode
  ) async throws {
    let codebase = Codebase(root: .sources([
      "Package.swift": "// swift-tools-version: \(version)\nlet package = Package(name: \"App\", targets: [.target(name: \"App\")])",
      "Sources/App/App.swift": "struct App {}",
    ]), including: ["Sources/**"])

    let files = try await codebase.files
    #expect(files.map(\.swiftLanguageMode) == [expected])
  }

  @Test(
    "Package mode overrides tools version",
    arguments: ["swiftLanguageModes", "swiftLanguageVersions"]
  )
  func declaredMode(label: String) async throws {
    let codebase = Codebase(root: .sources([
      "Package.swift": "// swift-tools-version: 6.0\nlet package = Package(name: \"App\", targets: [.target(name: \"App\")], \(label): [.v5])",
      "Sources/App/App.swift": "@available (swift, obsoleted: 1.0)\nstruct App {}",
    ]), including: ["Sources/**"])

    #expect(try await codebase.files.map(\.swiftLanguageMode) == [.v5])
  }

  @Test("Target modes override package mode with custom paths")
  func targetModes() async throws {
    let codebase = Codebase(root: .sources([
      "Package.swift": """
      // swift-tools-version: 6.0
      let package = Package(name: "App", targets: [
        .target(name: "Legacy", path: "Legacy", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "App"),
      ], swiftLanguageModes: [.v6])
      """,
      "Legacy/Old.swift": "@available (swift, obsoleted: 1.0)\nstruct Old {}",
      "Sources/App/App.swift": "struct App {}",
    ]), excluding: ["Package.swift"])

    let files = try await codebase.files
    #expect(files.map(\.swiftLanguageMode) == [.v5, .v6])
  }

  @Test("Nearest package supplies mode")
  func nestedPackages() async throws {
    let codebase = Codebase(root: .sources([
      "Package.swift": "// swift-tools-version: 6.0\nlet package = Package(name: \"Root\", targets: [])",
      "Packages/Legacy/Package.swift": "// swift-tools-version: 5.9\nlet package = Package(name: \"Legacy\", targets: [.target(name: \"Legacy\")])",
      "Packages/Legacy/Sources/Legacy/Old.swift": "@available (swift, obsoleted: 1.0)\nstruct Old {}",
    ]), including: ["**/Old.swift"])

    #expect(try await codebase.files.map(\.swiftLanguageMode) == [.v5])
  }

  @Test("Explicit mode overrides unresolved package settings")
  func unresolvedSettings() async throws {
    let root = Codebase.Root.sources([
      "Package.swift": "// swift-tools-version: 6.0\nlet package = Package(name: \"App\", targets: [.target(name: \"App\", swiftSettings: settings)])",
      "Sources/App/App.swift": "@available (swift, obsoleted: 1.0)\nstruct App {}",
    ])
    let automatic = Codebase(root: root, including: ["Sources/**"])
    await #expect(throws: CodebaseError
      .languageModeUnavailable(path: "/virtual/Package.swift"))
    {
      try await automatic.prepare()
    }
    let explicit = Codebase(
      root: root,
      including: ["Sources/**"],
      swiftLanguageMode: .v5
    )
    #expect(try await explicit.structs.count == 1)
  }

  @Test("Unknown source selection reports conflicting modes")
  func uncertainTarget() async throws {
    let codebase = Codebase(root: .sources([
      "Package.swift": """
      // swift-tools-version: 6.0
      let package = Package(name: "App", targets: [
        .target(name: "App", sources: selectedSources, swiftSettings: [.swiftLanguageMode(.v5)]),
      ])
      """,
      "Sources/App/App.swift": "struct App {}",
    ]), including: ["Sources/**"])

    await #expect(throws: CodebaseError
      .languageModeUnavailable(path: "/virtual/Package.swift"))
    {
      try await codebase.prepare()
    }
  }

  @Test("Unknown source selection preserves agreed mode")
  func agreedMode() async throws {
    let codebase = Codebase(root: .sources([
      "Package.swift": """
      // swift-tools-version: 6.0
      let package = Package(name: "App", targets: [
        .target(name: "App", sources: selectedSources),
      ])
      """,
      "Sources/App/App.swift": "struct App {}",
    ]), including: ["Sources/**"])

    #expect(try await codebase.files.map(\.swiftLanguageMode) == [.v6])
  }

  @Test("Manifest overlay changes mode before reusing parsed source")
  func manifestOverlay() async throws {
    let manifest = "// swift-tools-version: 6.0\nlet package = Package(name: \"App\", targets: [.target(name: \"App\")], swiftLanguageModes: [.v5])"
    let project = try TemporaryProject(files: [
      "Package.swift": manifest,
      "Sources/App/App.swift": "@available (swift, obsoleted: 1.0)\nstruct App {}",
    ])
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"]
    )
    try await codebase.prepare()
    let edited = codebase.usingOverlay(SourceOverlay([
      project.fileURL(for: "Package.swift").path: manifest.replacing(
        ".v5",
        with: ".v6"
      ),
    ]))

    await #expect(throws: CodebaseError.self) { try await edited.prepare() }
  }
}
