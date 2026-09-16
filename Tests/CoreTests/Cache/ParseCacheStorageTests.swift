import BylawsCore
import BylawsSemantics
import Foundation
import Testing

@Suite("Temporary cache storage")
struct ParseCacheStorageTests {
  @Test("Cache files remain until scope ends")
  func scopedCleanup() async throws {
    let directory: URL
    do {
      let storage = try ParseCacheTestStorage()
      directory = storage.directory
      let cache = storage.cache
      let source = "struct Model {}"
      let path = "/project/Model.swift"
      await cache.store(try FileCollector.collect(source: source, path: path))

      #expect(await cache.sourceFile(forSource: source, at: path) != nil)
      #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    #expect(!FileManager.default.fileExists(atPath: directory.path))
  }

  @Test("Thrown error removes cache directory")
  func throwingCleanup() throws {
    var directory: URL?

    #expect(throws: MockError.self) {
      let storage = try ParseCacheTestStorage()
      directory = storage.directory
      throw MockError()
    }

    let path = try #require(directory).path
    #expect(!FileManager.default.fileExists(atPath: path))
  }

  private struct MockError: Error {}
}
