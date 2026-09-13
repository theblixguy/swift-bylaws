import Bylaws
import BylawsCore
import BylawsTestSupport
import Foundation
import Testing

@Suite("Codebase editor text")
struct SourceOverlayTests {
  @Test("Query uses editor text for saved file")
  func savedFile() async throws {
    let project = try TemporaryProject(
      files: ["Sources/App/App.swift": "final class Saved {}"]
    )
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"]
    )

    let saved = try await codebase.classes
    let unsaved = try await codebase.usingOverlay(
      SourceOverlay([
        project.fileURL(for: "Sources/App/App.swift").path: "class Edited {}",
      ])
    ).classes

    #expect(saved.map(\.name) == ["Saved"])
    #expect(unsaved.map(\.name) == ["Edited"])
  }

  @Test("Query includes unsaved file")
  func unsavedFile() async throws {
    let project = try TemporaryProject(
      files: ["Sources/App/App.swift": "final class Saved {}"]
    )
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"]
    ).usingOverlay(
      SourceOverlay([
        project.fileURL(for: "Sources/App/New.swift").path: "class Added {}",
      ])
    )

    let classes = try await codebase.classes

    #expect(classes.map(\.name).sorted() == ["Added", "Saved"])
  }

  @Test("Replacement editor text leaves other files unchanged")
  func replacementText() async throws {
    let project = try TemporaryProject(
      files: [
        "Sources/App/App.swift": "final class Saved {}",
        "Sources/App/Other.swift": "final class Other {}",
      ]
    )
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"]
    )
    let path = project.fileURL(for: "Sources/App/App.swift").path

    _ = try await codebase.usingOverlay(
      SourceOverlay([path: "class First {}"])
    ).classes
    let classes = try await codebase.usingOverlay(
      SourceOverlay([path: "class Second {}"])
    ).classes

    #expect(classes.map(\.name).sorted() == ["Other", "Second"])
  }

  @Test("Query reads changed disk file after cache removal")
  func changedDiskFile() async throws {
    let project = try TemporaryProject(
      files: ["Sources/App/App.swift": "final class Saved {}"]
    )
    let root = project.rootURL.path
    let codebase = Codebase(root: .directory(root), including: ["Sources/**"])
    _ = try await codebase.usingOverlay(
      SourceOverlay([
        project.fileURL(for: "Sources/App/App.swift").path: "class Edited {}",
      ])
    ).classes

    try project.write("final class Rewritten {}", to: "Sources/App/App.swift")
    await CodebaseCache.shared.removeEntries(under: root)

    let classes = try await codebase.classes
    #expect(classes.map(\.name) == ["Rewritten"])
  }

  @Test("Query excludes editor files outside source patterns")
  func excludedFiles() async throws {
    let project = try TemporaryProject(
      files: ["Sources/App/App.swift": "final class Saved {}"]
    )
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"]
    ).usingOverlay(
      SourceOverlay([
        project.fileURL(for: "Tests/AppTests/New.swift").path:
          "class Excluded {}",
        "/elsewhere/Other.swift": "class Elsewhere {}",
      ])
    )

    let classes = try await codebase.classes

    #expect(classes.map(\.name) == ["Saved"])
  }

  @Test("Editor query reads changed disk files after cache removal")
  func changedDiskFilesWithOverlay() async throws {
    let project = try TemporaryProject(
      files: [
        "Sources/App/App.swift": "class Saved {}",
        "Sources/App/Other.swift": "class Before {}",
      ]
    )
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"]
    )
    let path = project.fileURL(for: "Sources/App/App.swift").path
    _ = try await codebase.usingOverlay(
      SourceOverlay([path: "class First {}"])
    ).classes

    try project.write("class After {}", to: "Sources/App/Other.swift")
    await CodebaseCache.shared.removeEntries(under: project.rootURL.path)
    let classes = try await codebase.usingOverlay(
      SourceOverlay([path: "class Second {}"])
    ).classes

    #expect(classes.map(\.name).sorted() == ["After", "Second"])
  }

  @Test("Query without editor text returns saved declarations")
  func savedDeclarations() async throws {
    let project = try TemporaryProject(
      files: ["Sources/App/App.swift": "final class Saved {}"]
    )
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"]
    )
    _ = try await codebase.usingOverlay(
      SourceOverlay([
        project.fileURL(for: "Sources/App/App.swift").path: "class Edited {}",
      ])
    ).classes

    let classes = try await codebase.classes

    #expect(classes.map(\.name) == ["Saved"])
  }

  @Test("Package dependency check uses editor manifest")
  func editedManifest() async throws {
    let project = try TemporaryProject(
      files: [
        "Package.swift": Self.manifest(declaringDomainForUI: true),
        "Sources/Domain/User.swift": "struct User {}",
        "Sources/UI/HomeView.swift": "import Domain",
      ]
    )
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"]
    )

    let saved = try await codebase.checkPackageDependencies()
    let unsaved = try await codebase.usingOverlay(
      SourceOverlay([
        project.fileURL(for: "Package.swift").path:
          Self.manifest(declaringDomainForUI: false),
      ])
    ).checkPackageDependencies()

    #expect(saved.undeclared.isEmpty)
    #expect(unsaved.undeclared.map(\.module) == ["Domain"])
  }

  private static func manifest(declaringDomainForUI: Bool) -> String {
    let dependencies = declaringDomainForUI ? ", dependencies: [\"Domain\"]" : ""
    return """
    // swift-tools-version: 6.0
    import PackageDescription

    let package = Package(
      name: "App",
      targets: [
        .target(name: "Domain"),
        .target(name: "UI"\(dependencies)),
      ]
    )
    """
  }
}
