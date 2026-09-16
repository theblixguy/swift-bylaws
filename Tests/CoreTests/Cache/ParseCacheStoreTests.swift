import BylawsSemantics
import Foundation
import Testing
@testable import BylawsCore

@Suite("Indexed parse cache")
struct ParseCacheStoreTests {
  @Test("Batch shares one file across cached models")
  func batch() async throws {
    let storage = try ParseCacheTestStorage()
    for index in 0..<100 {
      await storage.cache.store(try FileCollector.collect(
        source: "struct Model\(index) {}", path: "/App/\(index).swift"
      ))
    }
    await storage.cache.removeOldEntriesWhenDue()
    let packs = try FileManager.default.contentsOfDirectory(
      at: storage.cache.directory, includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "pack" }
    #expect(packs.count == 1)
    let reopened = try ParseCache.opening(directory: storage.directory)
    for index in 0..<100 {
      #expect(await reopened.sourceFile(
        forSource: "struct Model\(index) {}", at: "/Moved/\(index).swift"
      )?.structs.first?.name == "Model\(index)")
    }
  }

  @Test("Independent writers retain both batches")
  func writers() async throws {
    let storage = try ParseCacheTestStorage()
    let directory = storage.directory
    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<8 {
        group.addTask {
          let cache = try ParseCache.opening(directory: directory)
          await cache.store(try FileCollector.collect(
            source: "struct Model\(index) {}", path: "/App/\(index).swift"
          ))
          await cache.removeOldEntriesWhenDue()
        }
      }
      try await group.waitForAll()
    }
    let reader = try ParseCache.opening(directory: directory)
    for index in 0..<8 {
      #expect(await reader.sourceFile(
        forSource: "struct Model\(index) {}", at: "/App/\(index).swift"
      )?.structs.first?.name == "Model\(index)")
    }
  }

  @Test("Reader retains snapshot after another cache trims files")
  func readerDuringCleanup() async throws {
    let storage = try ParseCacheTestStorage()
    let source = "struct Model {}"
    await storage.cache.store(try FileCollector.collect(
      source: source,
      path: "/App/A.swift"
    ))
    await storage.cache.removeOldEntriesWhenDue()
    let reader = try ParseCache.opening(directory: storage.directory)
    let cleaner = try ParseCache.opening(
      directory: storage.directory,
      budget: 0
    )
    await cleaner.removeOldEntries()
    #expect(await reader
      .sourceFile(forSource: source, at: "/App/A.swift") != nil)
    let reopened = try ParseCache.opening(directory: storage.directory)
    #expect(await reopened
      .sourceFile(forSource: source, at: "/App/A.swift") == nil)
  }

  @Test("Compaction retains entries and reduces file count")
  func compaction() async throws {
    let storage = try ParseCacheTestStorage()
    let store = ParseCacheStore(
      directory: storage.cache.directory,
      schemaVersion: 11
    )
    for index in 0..<70 {
      await store.store(Data("value\(index)".utf8), for: "key\(index)")
      await store.flush()
    }
    await store.compactIfNeeded()
    let reopened = ParseCacheStore(
      directory: storage.cache.directory,
      schemaVersion: 11
    )
    for index in 0..<70 {
      #expect((await reopened.entry(for: "key\(index)"))?
        .data == Data("value\(index)".utf8))
    }
    let files = try FileManager.default.contentsOfDirectory(
      at: storage.cache.directory, includingPropertiesForKeys: nil
    )
    #expect(files.count == 1)
  }

  @Test("Payload corruption becomes a miss")
  func payloadCorruption() throws {
    let storage = try ParseCacheTestStorage()
    let url = storage.cache.directory.appendingPathComponent("data-v11.pack")
    _ = try ParseCachePack.write(["key": Data("original".utf8)], to: url)
    var bytes = try Data(contentsOf: url)
    bytes[0] ^= 1
    try bytes.write(to: url, options: .atomic)
    let pack = try ParseCachePack(url: url)
    #expect(pack.value(for: "key") == nil)
  }

  @Test("Truncated publication stays unreadable", arguments: [0, 1, 10, 40])
  func interruptedWrite(length: Int) async throws {
    let storage = try ParseCacheTestStorage()
    let url = storage.cache.directory.appendingPathComponent("data-v11.pack")
    _ = try ParseCachePack.write(["key": Data("original".utf8)], to: url)
    let bytes = try Data(contentsOf: url)
    try bytes.prefix(length).write(to: url, options: .atomic)
    #expect(throws: (any Error).self) { try ParseCachePack(url: url) }
    let store = ParseCacheStore(
      directory: storage.cache.directory,
      schemaVersion: 11
    )
    #expect((await store.entry(for: "key"))?.data == nil)
  }

  @Test("Index cannot associate a payload with a different key")
  func changedIndexKey() throws {
    let storage = try ParseCacheTestStorage()
    let url = storage.cache.directory.appendingPathComponent("data-v11.pack")
    _ = try ParseCachePack.write(["first": Data("payload".utf8)], to: url)
    var bytes = try Data(contentsOf: url)
    let range = try #require(bytes.range(of: Data("\"first\"".utf8)))
    bytes.replaceSubrange(range, with: Data("\"other\"".utf8))
    try bytes.write(to: url, options: .atomic)
    let pack = try ParseCachePack(url: url)
    #expect(pack.value(for: "other") == nil)
  }
}
