import BylawsCore
import Foundation
import Testing

@Suite("Parse cache policy")
struct ParseCachePolicyTests {
  @Test("Cache policy uses environment settings at resolution time")
  func constructionDefersEnvironment() {
    let codebase = Codebase(root: .sources([:]))
    let cache = URL(fileURLWithPath: "/custom/bylaws-cache")

    #expect(codebase.parseCachePolicy == .environment())
    #expect(
      codebase.parseCachePolicy.resolved(
        environment: [ParseCachePolicy.directoryEnvironmentKey: cache.path],
        defaultCacheDirectory: nil
      ) == .enabled(directory: cache, cachesTemporaryRoots: false)
    )
    #expect(
      codebase.parseCachePolicy.resolved(
        environment: [ParseCachePolicy.disableEnvironmentKey: "true"],
        defaultCacheDirectory: cache
      ) == .disabled
    )
  }

  @Test("Equal codebases can use independent cache policies")
  func independentPolicies() async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory
      .appendingPathComponent("bylaws-cache-policy-\(UUID().uuidString)")
    let cache = manager.temporaryDirectory
      .appendingPathComponent("bylaws-cache-output-\(UUID().uuidString)")
    try manager.createDirectory(
      at: root.appendingPathComponent("Sources/App"),
      withIntermediateDirectories: true
    )
    defer {
      try? manager.removeItem(at: root)
      try? manager.removeItem(at: cache)
    }
    try "struct Model {}".write(
      to: root.appendingPathComponent("Sources/App/Model.swift"),
      atomically: true,
      encoding: .utf8
    )
    let codebase = Codebase(
      root: .directory(root.path),
      including: ["Sources/**"]
    )

    _ = try await codebase.usingParseCache(.disabled).files
    #expect(!manager.fileExists(atPath: cache.path))

    _ = try await codebase.usingParseCache(
      .enabled(directory: cache, cachesTemporaryRoots: true)
    ).files
    let entries = manager.enumerator(atPath: cache.path)?
      .compactMap { $0 as? String } ?? []
    #expect(entries.contains { $0.hasSuffix(".bin") })
  }
}
