import Bylaws
import BylawsTestSupport
import Foundation
import Testing
@testable import BylawsCore

@Suite("Codebase process cache")
struct CodebaseCacheTests {
  @Test("Repeated directory roots share one cache configuration")
  func repeatedRoots() async throws {
    let project = try TemporaryProject(files: [
      "Model.swift": "struct Model {}",
    ])
    let cache = CodebaseCache()
    for _ in 0..<100 {
      _ = try await cache
        .parsedCodebase(for: Codebase(root: .directory(project.rootURL.path)))
    }
    #expect(await cache.cachedConfigurationCount == 1)
  }

  @Test("Temporary-directory matching respects path boundaries")
  func temporaryDirectoryBoundary() {
    #expect(CodebaseBuilder.contains("/tmp", in: "/tmp"))
    #expect(CodebaseBuilder.contains("/tmp/project", in: "/tmp"))
    #expect(!CodebaseBuilder.contains("/tmp-build/project", in: "/tmp"))
  }

  @Test("Equivalent directory paths share one parsed codebase")
  func equivalentDirectoryPathsShareParsedCodebase() async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory
      .appendingPathComponent("bylaws-codebase-cache-\(UUID().uuidString)")
    try manager.createDirectory(
      at: root.appendingPathComponent("Sources"),
      withIntermediateDirectories: true
    )
    defer { try? manager.removeItem(at: root) }

    let source = root.appendingPathComponent("Sources/Model.swift")
    try "struct Before {}".write(to: source, atomically: true, encoding: .utf8)
    let first =
      Codebase(root: .directory(root.appendingPathComponent(".").path))
    #expect(try await first.structs.map(\.name) == ["Before"])

    try "struct After {}".write(to: source, atomically: true, encoding: .utf8)
    let second = Codebase(root: .directory(root.path))
    #expect(try await second.structs.map(\.name) == ["Before"])
  }

  @Test("A parsed codebase remains available after its root is removed")
  func parsedCodebaseRemainsAfterRootRemoval() async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory
      .appendingPathComponent("bylaws-removed-root-\(UUID().uuidString)")
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    try "struct Model {}".write(
      to: root.appendingPathComponent("Model.swift"),
      atomically: true,
      encoding: .utf8
    )
    let codebase = Codebase(root: .directory(root.path))
    #expect(try await codebase.structs.map(\.name) == ["Model"])

    try manager.removeItem(at: root)

    #expect(try await codebase.structs.map(\.name) == ["Model"])
  }

  @Test("Package queries share one manifest analysis")
  func packageQueriesShareManifestAnalysis() async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory
      .appendingPathComponent("bylaws-package-analysis-\(UUID().uuidString)")
    try manager.createDirectory(
      at: root.appendingPathComponent("Sources/App"),
      withIntermediateDirectories: true
    )
    defer { try? manager.removeItem(at: root) }

    let manifest = root.appendingPathComponent("Package.swift")
    try Self.writeManifest(target: "App", to: manifest)
    try "struct Model {}".write(
      to: root.appendingPathComponent("Sources/App/Model.swift"),
      atomically: true,
      encoding: .utf8
    )
    let codebase = Codebase(
      root: .directory(root.path),
      including: ["Sources/**"]
    )
    #expect(try await codebase.importGraph().targets.map(\.name) == ["App"])

    try Self.writeManifest(target: "Changed", to: manifest)
    #expect(try await codebase.importGraph().targets.map(\.name) == ["App"])
  }

  private static func writeManifest(target: String, to url: URL) throws {
    let source = """
    // swift-tools-version: 6.0
    import PackageDescription

    let package = Package(
      name: "Sample",
      targets: [.target(name: "\(target)")]
    )
    """
    try source.write(to: url, atomically: true, encoding: .utf8)
  }
}
