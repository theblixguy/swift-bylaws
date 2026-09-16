import Bylaws
import BylawsCore
import Foundation
import Testing

private enum CacheTraitTestProject {
  static let codebase = Codebase(
    root: .directory(URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .path),
    including: ["ParseCacheTraitIntegrationTests.swift"]
  )
  static let codebaseFirstDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("bylaws-trait-\(UUID().uuidString)")
  static let cacheFirstDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("bylaws-trait-\(UUID().uuidString)")
  static let disabledDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("bylaws-trait-disabled-\(UUID().uuidString)")
}

@Suite(
  "Codebase preparation before cache trait",
  .codebase(CacheTraitTestProject.codebase),
  .parseCache(
    directory: CacheTraitTestProject.codebaseFirstDirectory,
    validation: .content
  )
)
struct ParseCacheTraitIntegrationTests {
  @Test("Preparation writes cache before test starts")
  func preparation() throws {
    let directory = CacheTraitTestProject.codebaseFirstDirectory
    defer { try? FileManager.default.removeItem(at: directory) }
    try expectPreparedCache(in: directory)
  }
}

@Suite(
  "Cache trait before codebase preparation",
  .parseCache(
    directory: CacheTraitTestProject.cacheFirstDirectory,
    validation: .content
  ),
  .codebase(CacheTraitTestProject.codebase)
)
struct ParseCacheBeforeCodebaseTests {
  @Test("Preparation uses cache trait before test starts")
  func preparation() throws {
    let directory = CacheTraitTestProject.cacheFirstDirectory
    defer { try? FileManager.default.removeItem(at: directory) }
    try expectPreparedCache(in: directory)
  }
}

@Suite("Parse cache trait query integration")
struct ParseCacheTraitQueryTests {
  @Test(
    "Zero budget queries source without cache writes",
    .parseCache(directory: CacheTraitTestProject.disabledDirectory, budget: 0)
  )
  func disabledDiskCache() async throws {
    let files = try await CacheTraitTestProject.codebase.files
    #expect(files.count == 1)
    #expect(!FileManager.default
      .fileExists(atPath: CacheTraitTestProject.disabledDirectory.path))
  }

  @Test("Stored codebase resolves each scope's cache policy")
  func queryPolicy() async throws {
    let storage = try ParseCacheTestStorage()
    let directory = storage.directory
    let source = directory.appendingPathComponent("Model.swift")
    try "class First {}".write(to: source, atomically: true, encoding: .utf8)
    let codebase = Codebase(
      root: .directory(directory.path),
      including: ["Model.swift"]
    )
    let first = try await ParseCacheConfiguration.$current.withValue(.init(
      directory: directory.appendingPathComponent("FirstCache"),
      validation: .metadata
    )) {
      try await codebase.classes.map(\.name)
    }
    try "class Other {}".write(to: source, atomically: true, encoding: .utf8)
    let secondDirectory = directory.appendingPathComponent("SecondCache")
    let second = try await ParseCacheConfiguration.$current.withValue(.init(
      directory: secondDirectory,
      validation: .content
    )) {
      try await codebase.classes.map(\.name)
    }

    #expect(first == ["First"])
    #expect(second == ["Other"])
    let cache = try ParseCache.opening(
      directory: secondDirectory,
      validation: .content
    )
    #expect(await cache.sourceFile(
      forSource: "class Other {}",
      at: source.path
    ) != nil)
  }
}

private func expectPreparedCache(
  in directory: URL,
  sourceLocation: SourceLocation = #_sourceLocation
) throws {
  let codebase = try #require(Codebase.current, sourceLocation: sourceLocation)
  #expect(codebase.parseCachePolicy.resolved() == .enabled(
    directory: directory,
    cachesTemporaryRoots: true,
    validation: .content
  ), sourceLocation: sourceLocation)
  let entries = try #require(
    FileManager.default
      .enumerator(atPath: directory.path),
    sourceLocation: sourceLocation
  )
  .compactMap { $0 as? String }
  #expect(
    entries.contains { $0.hasSuffix(".pack") },
    sourceLocation: sourceLocation
  )
}
