import BylawsSemantics
import Foundation
import Testing
@testable import BylawsCore

@Suite("Portable parse cache")
struct ParseCachePortabilityTests {
  @Test("Cache restores declaration and call locations", arguments: [
    "/worker/checkout/Sources/Model.swift",
    "/sandbox/renamed/Other/模型.swift",
  ])
  func restoredLocations(path: String) async throws {
    let storage = try ParseCacheTestStorage()
    let source = """
    import Foundation
    protocol Loading {
      var value: Int { get }
      func load()
    }
    class Model {
      var value = makeValue()
      init() { prepare() }
      func load() { fetch("message", privacy: .public) }
      struct Nested {}
    }
    actor Store {}
    enum State {
      case ready
    }
    extension Model: Loading {}
    typealias Item = Model
    #Preview { Model() }
    """
    let parsed = try FileCollector.collect(
      source: source, path: "/original/Sources/Model.swift"
    )
    await storage.cache.store(parsed)

    let loaded = try #require(
      await storage.cache.sourceFile(forSource: source, at: path)
    )
    let expected = try FileCollector.collect(source: source, path: path)
    let locations = locations(in: loaded)

    #expect(loaded.path == path)
    #expect(loaded.name == expected.name)
    #expect(loaded.sourceText == source)
    #expect(locations.count > 15)
    #expect(locations.allSatisfy { $0.filePath == path })
    #expect(locations == self.locations(in: expected))
    let model = try #require(loaded.classes.first)
    #expect(model.sourceText == expected.classes.first?.sourceText)
    #expect(loaded.calls == expected.calls)
    let argument = try #require(loaded.calls.first { $0.memberName == "fetch" }?
      .arguments.last)
    #expect(argument.expression?.referenceName == "public")
    #expect(argument.expression?.location.filePath == path)
  }

  @Test("Cache bytes exclude checkout path")
  func storedPaths() throws {
    let source = "class Model {}"
    let original = try FileCollector.collect(
      source: source, path: "/original/Model.swift"
    )
    let moved = try FileCollector.collect(
      source: source, path: "/other/Renamed.swift"
    )
    let first = CacheEncoder()
    first.encode(original)
    let second = CacheEncoder()
    second.encode(moved)

    #expect(first.bytes == second.bytes)
    #expect(!String(decoding: first.bytes, as: UTF8.self).contains("/original"))
  }

  @Test("Copied cache reuses models in either validation mode", arguments: [
    ParseCacheConfiguration.Validation.metadata, .content,
  ])
  func copiedCache(
    validation: ParseCacheConfiguration.Validation
  ) async throws {
    let source = "class Model { func load() {} }"
    let files = ["Sources/Model.swift": source, "Sources/Other.swift": source]
    let storage = try ParseCacheTestStorage()
    let original = storage.directory.appendingPathComponent("original")
    let moved = storage.directory.appendingPathComponent("renamed")
    let manager = FileManager.default
    for root in [original, moved] {
      for (path, text) in files {
        let file = root.appendingPathComponent(path)
        try manager.createDirectory(
          at: file.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try text.write(to: file, atomically: true, encoding: .utf8)
      }
    }
    let originalCodebase = Codebase(
      root: .directory(original.path), swiftLanguageMode: .v6
    ).usingParseCache(
      .enabled(
        directory: storage.directory, cachesTemporaryRoots: true,
        validation: validation
      )
    )
    try #require(try await originalCodebase.files.count == 2)

    let copiedDirectory = storage.directory.appendingPathComponent("copied")
    try manager.createDirectory(
      at: copiedDirectory, withIntermediateDirectories: true
    )
    try manager.copyItem(
      at: storage.cache.directory,
      to: copiedDirectory.appendingPathComponent("Bylaws")
    )
    let cache = try ParseCache.opening(directory: copiedDirectory)
    let entry = try #require(manager.contentsOfDirectory(
      at: cache.directory, includingPropertiesForKeys: nil
    ).first { $0.pathExtension == "pack" })
    let savedDate = Date(timeIntervalSince1970: 1_000_000)
    try manager.setAttributes(
      [.modificationDate: savedDate], ofItemAtPath: entry.path
    )
    let codebase = Codebase(
      root: .directory(moved.path), swiftLanguageMode: .v6
    ).usingParseCache(
      .enabled(
        directory: copiedDirectory, cachesTemporaryRoots: true,
        validation: validation
      )
    )

    let loaded = try await codebase.files
    let attributes = try manager.attributesOfItem(atPath: entry.path)

    #expect(loaded.map(\.path).sorted() == files.keys.map {
      moved.appendingPathComponent($0).path
    }.sorted())
    for file in loaded {
      #expect(file.classes.first?.location.filePath == file.path)
      #expect(file.functions.first?.location.filePath == file.path)
    }
    let entries = try manager.contentsOfDirectory(
      at: cache.directory, includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "pack" }
    let contentKey = ParseCache.key(forSource: source)
    let models = try entries.map { try ParseCachePack(url: $0) }
      .count { $0.keys.contains(contentKey) }
    #expect(models == 1)
    #expect(attributes[.modificationDate] as? Date == savedDate)
  }

  private func locations(in file: SourceFile) -> [DeclarationLocation] {
    var result = [file.location]
    result += file.imports.map(\.location)
    result += file.types.map(\.location)
    result += file.protocols.map(\.location)
    result += file.extensions.map(\.location)
    result += file.functions.map(\.location)
    result += file.properties.map(\.location)
    result += file.initializers.map(\.location)
    result += file.typealiases.map(\.location)
    result += file.calls.map(\.location)
    result += file.enums.flatMap(\.cases).map(\.location)
    result += file.protocols.flatMap(\.requiredFunctions).map(\.location)
    result += file.protocols.flatMap(\.requiredProperties).map(\.location)
    return result
  }
}
