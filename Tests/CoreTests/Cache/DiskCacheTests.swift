import Foundation
import Testing
@testable import BylawsCore

@Suite("Disk cache storage")
struct DiskCacheTests {
  @Test("Entries write, read and remove data")
  func entryLifecycle() throws {
    let storage = try ParseCacheTestStorage()
    let cache = try DiskCache.opening(
      directory: storage.directory,
      budget: ParseCache.defaultBudget
    )
    let data = Data("result".utf8)

    try cache.write(data, toEntryNamed: "result.json")
    #expect(cache.data(forEntryNamed: "result.json") == data)

    try cache.removeEntry(named: "result.json")
    #expect(cache.data(forEntryNamed: "result.json") == nil)
  }

  @Test("Symbolic links cannot change files outside the cache")
  func rejectsSymbolicLink() throws {
    let storage = try ParseCacheTestStorage()
    let cache = try DiskCache.opening(
      directory: storage.directory,
      budget: ParseCache.defaultBudget
    )
    let target = storage.directory.appendingPathComponent("target.json")
    let entry = cache.directory.appendingPathComponent("result.json")
    let original = Data("original".utf8)
    try original.write(to: target)
    try FileManager.default.createSymbolicLink(
      at: entry,
      withDestinationURL: target
    )

    #expect(
      throws: DiskCache.Error.entryIsSymbolicLink(path: entry.path)
    ) {
      try cache.write(Data("changed".utf8), toEntryNamed: "result.json")
    }
    #expect(try Data(contentsOf: target) == original)
  }

  @Test("Cleanup counts every cache entry against the budget")
  func sharedBudget() throws {
    let storage = try ParseCacheTestStorage()
    let cache = try DiskCache.opening(
      directory: storage.directory,
      budget: 1
    )
    try cache.write(Data("result".utf8), toEntryNamed: "result.json")

    cache.removeOldEntries(removingEntriesWhere: { _ in false })

    #expect(cache.data(forEntryNamed: "result.json") == nil)
  }
}
