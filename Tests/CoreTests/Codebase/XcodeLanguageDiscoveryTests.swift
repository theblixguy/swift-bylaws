import BylawsCore
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Xcode language discovery")
struct XcodeLanguageDiscoveryTests {
  @Test("Default mode skips Xcode project contents")
  func defaultMode() async throws {
    let project = try TemporaryProject(files: [
      "App.xcodeproj/project.pbxproj": "not a property list",
      "App/App.swift": "struct App {}",
    ])
    let codebase = Codebase(root: .directory(project.rootURL.path))

    #expect(codebase.swiftLanguageMode == .automatic(.swiftPM))
    #expect(try await codebase.files.map(\.swiftLanguageMode) == [.v6])
  }

  @Test("Opt-in reads Xcode mode without building")
  func enabled() async throws {
    let project = try TemporaryProject(files: [
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

  @Test("Explicit mode skips Xcode settings")
  func explicitMode() async throws {
    let project = try TemporaryProject(files: [
      "App.xcodeproj/project.pbxproj": "not a property list",
      "App/Legacy.swift": "@available (swift, obsoleted: 1.0)\nstruct Legacy {}",
    ])
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      swiftLanguageMode: .v5
    )

    #expect(try await codebase.files.map(\.swiftLanguageMode) == [.v5])
  }

  @Test("SwiftPM mode takes precedence over Xcode discovery")
  func packageMode() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "// swift-tools-version: 5.9\nlet package = Package(name: \"App\", targets: [.target(name: \"App\")])",
      "App.xcodeproj/project.pbxproj": "not a property list",
      "Sources/App/App.swift": "struct App {}",
    ])
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"],
      swiftLanguageMode: .automatic([.swiftPM, .xcode])
    )

    #expect(try await codebase.files.map(\.swiftLanguageMode) == [.v5])
  }

  @Test("Opt-in reports unresolved Xcode mode")
  func malformedProject() async throws {
    let project = try TemporaryProject(files: [
      "App.xcodeproj/project.pbxproj": "not a property list",
      "App/App.swift": "struct App {}",
    ])
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      swiftLanguageMode: .automatic(.xcode)
    )

    await #expect(throws: CodebaseError.languageModeUnavailable(
      path: project.fileURL(for: "App.xcodeproj/project.pbxproj").path
    )) {
      try await codebase.prepare()
    }
  }

  @Test("Cached codebases retain separate discovery settings")
  func cachedModes() async throws {
    let project = try TemporaryProject(files: [
      "App.xcodeproj/project.pbxproj": xcodeProjectSource(),
      "App/App.swift": "struct App {}",
    ])
    let root = Codebase.Root.directory(project.rootURL.path)
    let standard = Codebase(root: root).usingParseCache(.disabled)
    let discovered = Codebase(root: root, swiftLanguageMode: .automatic(.xcode))
      .usingParseCache(.disabled)
      .usingOverlay(.empty)

    #expect(try await standard.files.map(\.swiftLanguageMode) == [.v6])
    #expect(try await discovered.files.map(\.swiftLanguageMode) == [.v5])
    #expect(try await standard.files.map(\.swiftLanguageMode) == [.v6])
  }
}
