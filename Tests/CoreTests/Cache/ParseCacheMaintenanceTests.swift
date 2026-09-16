import BylawsCore
import BylawsSemantics
import Foundation
import Testing

@Suite("Parse cache maintenance")
struct ParseCacheMaintenanceTests {
  @Test("Trimming removes the oldest entries until the budget fits")
  func trimsToBudget() throws {
    let testCache = try ParseCacheTestStorage(budget: 1)
    let cache = testCache.cache
    for index in 1...3 {
      let path = "/App/File\(index).swift"
      let source = "class Type\(index) {}"
      cache.store(
        try FileCollector.collect(source: source, path: path)
      )
    }

    cache.removeOldEntries()
    let remaining = try FileManager.default.contentsOfDirectory(
      at: cache.directory,
      includingPropertiesForKeys: nil
    )
    #expect(remaining.count <= 1)
  }

  @Test("Trimming preserves files beside the owned cache directory")
  func trimmingPreservesUnrelatedFiles() throws {
    let testCache = try ParseCacheTestStorage(budget: 1)
    let cache = testCache.cache
    let unrelated = testCache.directory.appendingPathComponent("notes.txt")
    let contents = Data("keep this".utf8)
    try contents.write(to: unrelated)
    let path = "/App/File.swift"
    let source = "class Type {}"
    cache.store(
      try FileCollector.collect(source: source, path: path)
    )

    cache.removeOldEntries()

    #expect(try Data(contentsOf: unrelated) == contents)
    #expect(
      cache.directory.deletingLastPathComponent().standardizedFileURL.path
        == testCache.directory.standardizedFileURL.path
    )
  }

  @Test("Trimming removes earlier cache formats", arguments: [
    "File-abc-v1.bin", "OldProject/File-abc-v8.bin",
  ])
  func removesSupersededSchemaEntries(name: String) throws {
    let testCache = try ParseCacheTestStorage()
    let cache = testCache.cache
    let path = "/App/File.swift"
    let source = "class Type {}"
    cache.store(
      try FileCollector.collect(source: source, path: path)
    )
    let current = cache.entry(forSource: source)
    let superseded = current.deletingLastPathComponent()
      .appendingPathComponent(name)
    try FileManager.default.createDirectory(
      at: superseded.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("stale".utf8).write(to: superseded)

    cache.removeOldEntries()

    #expect(!FileManager.default.fileExists(atPath: superseded.path))
    #expect(cache.sourceFile(forSource: source, at: path) != nil)
  }

  @Test("A symlink in place of the owned directory fails the open")
  func rejectsSymlinkedOwnedDirectory() throws {
    let manager = FileManager.default
    let container = manager.temporaryDirectory
      .appendingPathComponent("bylaws-cache-container-\(UUID().uuidString)")
    let target = manager.temporaryDirectory
      .appendingPathComponent("bylaws-cache-target-\(UUID().uuidString)")
    try manager.createDirectory(
      at: container,
      withIntermediateDirectories: true
    )
    try manager.createDirectory(at: target, withIntermediateDirectories: true)
    defer {
      try? manager.removeItem(at: container)
      try? manager.removeItem(at: target)
    }
    try manager.createSymbolicLink(
      at: container.appendingPathComponent("Bylaws"),
      withDestinationURL: target
    )
    let unrelated = target.appendingPathComponent("notes.txt")
    let contents = Data("keep this".utf8)
    try contents.write(to: unrelated)

    #expect(
      throws: ParseCacheError.directoryIsSymbolicLink(
        path: container.appendingPathComponent("Bylaws").path
      )
    ) {
      try ParseCache.opening(directory: container, budget: 1)
    }
    #expect(try Data(contentsOf: unrelated) == contents)
  }

  @Test("A trim that ran today does not run again")
  func trimsOnceADay() throws {
    let testCache = try ParseCacheTestStorage(budget: 1)
    let cache = testCache.cache
    let path = "/App/File.swift"
    let source = "class Type {}"
    cache.removeOldEntriesWhenDue()
    cache.store(
      try FileCollector.collect(source: source, path: path)
    )

    cache.removeOldEntriesWhenDue()

    #expect(cache.sourceFile(forSource: source, at: path) != nil)
  }

  @Test("Lower budget applies during daily maintenance interval")
  func reducedBudget() throws {
    let storage = try ParseCacheTestStorage()
    let source = "class Model {}"
    let path = "/App/Model.swift"
    storage.cache.store(try FileCollector.collect(source: source, path: path))
    storage.cache.removeOldEntriesWhenDue()
    #expect(storage.cache.sourceFile(forSource: source, at: path) != nil)

    let smaller = try ParseCache.opening(
      directory: storage.directory,
      budget: 1
    )
    smaller.removeOldEntriesWhenDue()

    #expect(smaller.sourceFile(forSource: source, at: path) == nil)
  }

  @Test("Lower target applies after an increase within daily interval")
  func budgetChanges() throws {
    let storage = try ParseCacheTestStorage(budget: 1)
    storage.cache.removeOldEntriesWhenDue()
    let source = "class Model {}"
    let path = "/App/Model.swift"
    let larger = try ParseCache.opening(directory: storage.directory)
    larger.store(try FileCollector.collect(source: source, path: path))
    larger.removeOldEntriesWhenDue()
    #expect(larger.sourceFile(forSource: source, at: path) != nil)

    storage.cache.removeOldEntriesWhenDue()

    #expect(storage.cache.sourceFile(forSource: source, at: path) == nil)
  }
}
