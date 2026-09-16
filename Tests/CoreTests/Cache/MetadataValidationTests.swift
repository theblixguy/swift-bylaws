import BylawsSemantics
import Foundation
import Testing
@testable import BylawsCore

@Suite("Parse cache metadata validation")
struct MetadataValidationTests {
  @Test("Unchanged source reuses metadata without new packs")
  func unchangedSource() async throws {
    let storage = try ParseCacheTestStorage()
    let source = try write("class Model {}", in: storage.directory)
    let now = Date().addingTimeInterval(3)
    let first = try await storage.cache.collect(at: source.path, now: now)
    await storage.cache.removeOldEntriesWhenDue()
    let before = try packs(in: storage.cache.directory)
    let reopened = try ParseCache.opening(directory: storage.directory)
    let metadata = try #require(SourceMetadata.read(at: source.path))

    let hit = await reopened.sourceFile(
      at: source.path, matching: metadata, swiftLanguageMode: .v6
    )
    let second = try await reopened.collect(at: source.path, now: now)
    await reopened.removeOldEntriesWhenDue()

    #expect(hit?.classes.first?.name == "Model")
    #expect(first.sourceText == second.sourceText)
    #expect(try packs(in: storage.cache.directory) == before)
  }

  @Test("Same-size edits with restored modification time use changed source")
  func restoredModificationTime() async throws {
    let storage = try ParseCacheTestStorage()
    let source = try write("class First {}", in: storage.directory)
    let date = Date(timeIntervalSince1970: 1_700_000_000.5)
    try FileManager.default.setAttributes(
      [.modificationDate: date], ofItemAtPath: source.path
    )
    _ = try await storage.cache.collect(
      at: source.path,
      now: Date().addingTimeInterval(3)
    )
    let before = try #require(SourceMetadata.read(at: source.path))
    try "class Other {}".write(to: source, atomically: false, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.modificationDate: date], ofItemAtPath: source.path
    )
    let after = try #require(SourceMetadata.read(at: source.path))

    let file = try await storage.cache.collect(
      at: source.path,
      now: Date().addingTimeInterval(3)
    )

    #expect(before.size == after.size)
    #expect(before.inode == after.inode)
    #expect(before.modified == after.modified)
    #expect(before.changed != after.changed)
    #expect(file.classes.first?.name == "Other")
  }

  @Test("Atomic file replacement uses new source")
  func replacement() async throws {
    let storage = try ParseCacheTestStorage()
    let source = try write("class First {}", in: storage.directory)
    _ = try await storage.cache.collect(
      at: source.path,
      now: Date().addingTimeInterval(3)
    )
    let before = try #require(SourceMetadata.read(at: source.path))
    try "class Other {}".write(to: source, atomically: true, encoding: .utf8)
    let after = try #require(SourceMetadata.read(at: source.path))

    let file = try await storage.cache.collect(
      at: source.path,
      now: Date().addingTimeInterval(3)
    )

    #expect(before.inode != after.inode)
    #expect(file.classes.first?.name == "Other")
  }

  @Test("Edit after initial stat rejects cached metadata")
  func changedDuringLookup() async throws {
    let storage = try ParseCacheTestStorage()
    let source = try write("class First {}", in: storage.directory)
    _ = try await storage.cache.collect(
      at: source.path,
      now: Date().addingTimeInterval(3)
    )
    let before = try #require(SourceMetadata.read(at: source.path))
    try "class Other {}".write(to: source, atomically: false, encoding: .utf8)

    let hit = await storage.cache.sourceFile(
      at: source.path, matching: before, swiftLanguageMode: .v6
    )

    #expect(hit == nil)
  }

  @Test("Recent metadata falls back without recording a path entry")
  func recentSource() async throws {
    let storage = try ParseCacheTestStorage()
    let source = try write("class Model {}", in: storage.directory)
    let now = Date()

    let file = try await storage.cache.collect(at: source.path, now: now)
    let key = ParseCache.metadataKey(for: source.path, swiftLanguageMode: .v6)

    #expect(file.classes.first?.name == "Model")
    #expect(await storage.cache.storage.entry(for: key) == nil)
  }

  @Test("Content validation reads changed source across mode switches")
  func switchesModes() async throws {
    let storage = try ParseCacheTestStorage()
    let source = try write("class First {}", in: storage.directory)
    _ = try await storage.cache.collect(
      at: source.path,
      now: Date().addingTimeInterval(3)
    )
    await storage.cache.removeOldEntriesWhenDue()
    try "class Other {}".write(to: source, atomically: false, encoding: .utf8)
    let content = try ParseCache.opening(
      directory: storage.directory,
      validation: .content
    )

    let changed = try await content.collect(at: source.path)
    await content.removeOldEntriesWhenDue()
    let metadata = try ParseCache.opening(directory: storage.directory)
    let switched = try await metadata.collect(
      at: source.path,
      now: Date().addingTimeInterval(3)
    )

    #expect(changed.classes.first?.name == "Other")
    #expect(switched.classes.first?.name == "Other")
    #expect(await metadata.sourceFile(
      forSource: "class First {}",
      at: source.path
    ) != nil)
    #expect(await metadata.sourceFile(
      forSource: "class Other {}",
      at: source.path
    ) != nil)
  }

  @Test("Damaged records fall back to source", arguments: ["metadata", "model"])
  func damagedRecords(record: String) async throws {
    let storage = try ParseCacheTestStorage()
    let source = try write("class Model {}", in: storage.directory)
    _ = try await storage.cache.collect(
      at: source.path,
      now: Date().addingTimeInterval(3)
    )
    let key = record == "metadata"
      ? ParseCache.metadataKey(for: source.path, swiftLanguageMode: .v6)
      : ParseCache.key(forSource: "class Model {}")
    await storage.cache.storage.store(Data("damaged".utf8), for: key)

    let file = try await storage.cache.collect(
      at: source.path,
      now: Date().addingTimeInterval(3)
    )

    #expect(file.classes.first?.name == "Model")
  }

  @Test("Missing model behind metadata falls back to source")
  func missingModel() async throws {
    let storage = try ParseCacheTestStorage()
    let source = try write("class Model {}", in: storage.directory)
    let record = ParseCache.MetadataRecord(
      metadata: try #require(SourceMetadata.read(at: source.path)),
      contentKey: "missing"
    )
    await storage.cache.storage.store(
      try JSONEncoder().encode(record),
      for: ParseCache.metadataKey(for: source.path, swiftLanguageMode: .v6)
    )

    let file = try await storage.cache.collect(
      at: source.path,
      now: Date().addingTimeInterval(3)
    )

    #expect(file.classes.first?.name == "Model")
  }

  @Test("Metadata keys separate paths and language modes")
  func pathAndLanguage() async throws {
    let storage = try ParseCacheTestStorage()
    let source = try write("class Model {}", in: storage.directory)
    let other = storage.directory.appendingPathComponent("Other.swift")
    try FileManager.default.copyItem(at: source, to: other)
    _ = try await storage.cache.collect(
      at: source.path,
      swiftLanguageMode: .v5,
      now: Date().addingTimeInterval(3)
    )
    let modeKey = ParseCache.metadataKey(
      for: source.path,
      swiftLanguageMode: .v6
    )
    let pathKey = ParseCache.metadataKey(
      for: other.path,
      swiftLanguageMode: .v5
    )

    #expect(await storage.cache.storage.entry(for: modeKey) == nil)
    #expect(await storage.cache.storage.entry(for: pathKey) == nil)
    let file = try await storage.cache.collect(
      at: other.path,
      swiftLanguageMode: .v6,
      now: Date().addingTimeInterval(3)
    )
    #expect(file.path == other.path)
    #expect(file.swiftLanguageMode == .v6)
  }

  @Test("Deleted source cannot reuse cached metadata")
  func deletedSource() async throws {
    let storage = try ParseCacheTestStorage()
    let source = try write("class Model {}", in: storage.directory)
    _ = try await storage.cache.collect(
      at: source.path,
      now: Date().addingTimeInterval(3)
    )
    try FileManager.default.removeItem(at: source)

    let cache = storage.cache
    await #expect(throws: ParseError.self) {
      try await cache.collect(at: source.path)
    }
  }

  @Test("Parallel codebases select validation independently")
  func parallelModes() async throws {
    let storage = try ParseCacheTestStorage()
    _ = try write("class Model {}", in: storage.directory)
    let metadata = Codebase(
      root: .directory(storage.directory.path), including: ["Model.swift"],
      parseCache: .init(directory: storage.directory, validation: .metadata)
    )
    let content = Codebase(
      root: .directory(storage.directory.path), including: ["Model.swift"],
      parseCache: .init(directory: storage.directory, validation: .content)
    )
    async let first = metadata.classes
    async let second = content.classes
    let selections = try await (first, second)

    #expect(selections.0.map(\.name) == ["Model"])
    #expect(selections.1.map(\.name) == ["Model"])
    #expect(metadata.parseCachePolicy != content.parseCachePolicy)
  }

  private func write(_ text: String, in directory: URL) throws -> URL {
    let url = directory.appendingPathComponent("Model.swift")
    try text.write(to: url, atomically: false, encoding: .utf8)
    return url
  }

  private func packs(in directory: URL) throws -> Set<String> {
    Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)
      .filter { $0.hasSuffix(".pack") })
  }
}
