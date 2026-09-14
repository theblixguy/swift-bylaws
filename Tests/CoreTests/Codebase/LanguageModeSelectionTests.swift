import BylawsCore
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Language-mode selection")
struct LanguageModeSelectionTests {
  @Test("Selected projects determine each file's mode", arguments: [
    (
      Codebase.LanguageMode.automatic(.swiftPM),
      SwiftLanguageMode.v6,
      SwiftLanguageMode.v5
    ),
    (.automatic(.xcode), .v4, .v4),
    (.automatic([.swiftPM, .xcode]), .v4, .v5),
    (.automatic([]), .v6, .v6),
  ])
  func projectSelection(
    selection: Codebase.LanguageMode,
    appMode: SwiftLanguageMode,
    packageMode: SwiftLanguageMode
  ) async throws {
    let project = try TemporaryProject(files: [
      "App.xcodeproj/project.pbxproj": xcodeProjectSource(
        targetSettings: "SWIFT_VERSION = 4.0;"
      ),
      "App/App.swift": "struct App {}",
      "Local/Package.swift": "// swift-tools-version: 5.9\nlet package = Package(name: \"Local\", targets: [.target(name: \"Local\")])",
      "Local/Sources/Local/Local.swift": "struct Local {}",
    ])
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["App/**", "Local/Sources/**"],
      swiftLanguageMode: selection
    )

    #expect(try await codebase.files.map(\.swiftLanguageMode) == [
      appMode,
      packageMode,
    ])
  }

  @Test("Xcode selection skips malformed SwiftPM settings")
  func skipsPackage() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "let package =",
      "App.xcodeproj/project.pbxproj": xcodeProjectSource(),
      "App/Legacy.swift": "@available (swift, obsoleted: 1.0)\nstruct Legacy {}",
    ])
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["App/**"],
      swiftLanguageMode: .automatic(.xcode)
    )

    #expect(try await codebase.files.map(\.swiftLanguageMode) == [.v5])
  }

  @Test("Explicit modes skip malformed project settings", arguments: [
    (Codebase.LanguageMode.v4, SwiftLanguageMode.v4),
    (.v5, .v5),
    (.v6, .v6),
  ])
  func explicitMode(
    selection: Codebase.LanguageMode,
    expected: SwiftLanguageMode
  ) async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "let package =",
      "App.xcodeproj/project.pbxproj": "not a property list",
      "App/App.swift": "struct App {}",
    ])
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["App/**"],
      swiftLanguageMode: selection
    )

    #expect(try await codebase.files.map(\.swiftLanguageMode) == [expected])
  }

  @Test("Unresolved SwiftPM settings fail combined discovery")
  func unresolvedPackage() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "// swift-tools-version: 6.0\nlet package = Package(name: \"App\", targets: [.target(name: \"App\", swiftSettings: settings)])",
      "App.xcodeproj/project.pbxproj": xcodeProjectSource(),
      "Sources/App/App.swift": "struct App {}",
    ])
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"],
      swiftLanguageMode: .automatic([.swiftPM, .xcode])
    )

    await #expect(throws: CodebaseError.languageModeUnavailable(
      path: project.fileURL(for: "Package.swift").path
    )) {
      try await codebase.prepare()
    }
  }

  @Test("Inline sources respect project selection", arguments: [
    (Codebase.LanguageMode.automatic(.swiftPM), SwiftLanguageMode.v5),
    (.automatic(.xcode), .v6),
    (.automatic([.swiftPM, .xcode]), .v5),
    (.automatic([]), .v6),
  ])
  func inlineSelection(
    selection: Codebase.LanguageMode,
    expected: SwiftLanguageMode
  ) async throws {
    let codebase = Codebase(
      root: .sources([
        "Package.swift": "// swift-tools-version: 5.9\nlet package = Package(name: \"App\", targets: [.target(name: \"App\")])",
        "Sources/App/App.swift": "struct App {}",
      ]),
      including: ["Sources/**"],
      swiftLanguageMode: selection
    )

    #expect(try await codebase.files.map(\.swiftLanguageMode) == [expected])
  }
}
