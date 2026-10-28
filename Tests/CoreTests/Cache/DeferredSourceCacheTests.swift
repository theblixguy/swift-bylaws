import BylawsSemantics
import Foundation
import Testing
@testable import BylawsCore

@Suite("Deferred cached source")
struct DeferredSourceCacheTests {
  @Test("Cache encoding and decoding leave source unloaded")
  func deferredProjections() throws {
    let original = try FileCollector.collect(
      source: """
      @MainActor struct Store {
        var value = 1
        func load() { fetch(value: 1) }
      }
      """, path: "/virtual/Store.swift"
    )
    #expect(!original.sourceBuffer.hasLoadedSnapshot)
    let encoded = CacheEncoder()
    encoded.encode(original)
    #expect(!original.sourceBuffer.hasLoadedSnapshot)

    let decoder = try CacheDecoder(encoded.bytes, path: original.path)
    let decoded = try SourceFile(from: decoder)
    #expect(decoder.isAtEnd)
    #expect(decoded.structs.map(\.name) == ["Store"])
    #expect(decoded.structs[0].attributes.map(\.name) == ["MainActor"])
    #expect(decoded.properties.map(\.name) == ["value"])
    #expect(decoded.functions.map(\.name) == ["load"])
    #expect(decoded.calls.map(\.memberName) == ["fetch"])
    #expect(!decoded.sourceBuffer.hasLoadedSnapshot)

    #expect(try decoded.structs[0].nameSource.text == "Store")
    #expect(try decoded.functions[0].bodySource.text == " fetch(value: 1) ")
    #expect(decoded.sourceBuffer.hasLoadedSnapshot)
    let reencoded = CacheEncoder()
    reencoded.encode(decoded)
    #expect(reencoded.bytes == encoded.bytes)
  }

  @Test("Cache rejects source ranges outside scalar boundaries", arguments: [
    -1..<1, 0..<7, 2..<3, 3..<6,
  ])
  func rejectsMalformedRanges(range: Range<Int>) throws {
    let encoder = CacheEncoder()
    encoder.encode("//🦊")
    encoder.encode(range)
    let decoder = try CacheDecoder(encoder.bytes, path: "/virtual/App.swift")
    decoder.bindSource(to: .v6)

    #expect(throws: CacheDecoder.Malformed.self) {
      try ParsedSource(from: decoder)
    }
    #expect(!decoder.source.hasLoadedSnapshot)
  }

  @Test("Cached ranges distinguish repeated attributes and bindings")
  func distinctRanges() async throws {
    let storage = try ParseCacheTestStorage()
    let source = """
    @Tag("first") @Tag("second")
    struct Store {
      var first = 1, second = 2
    }
    """
    let path = "/virtual/Store.swift"
    await storage.cache.store(try FileCollector.collect(
      source: source, path: path
    ))
    let decoded = try #require(await storage.cache.sourceFile(
      forSource: source, at: path
    ))

    #expect(!decoded.sourceBuffer.hasLoadedSnapshot)
    let attributes = try #require(decoded.structs.first).attributes
    #expect(try attributes.map { try $0.source.text } == [
      "@Tag(\"first\")", "@Tag(\"second\")",
    ])
    #expect(try decoded.properties.map { try $0.nameSource.text } == [
      "first", "second",
    ])
    #expect(try decoded.properties.map { try $0.source.text } == [
      "first = 1,", "second = 2",
    ])
  }

  @Test("Deferred source preserves bytes after disk changes", arguments: [
    false, true,
  ])
  func capturedBytes(removed: Bool) async throws {
    let storage = try ParseCacheTestStorage()
    let file = storage.directory.appendingPathComponent("Store.swift")
    let source = "struct Store { func load() { fetch(value: 1) } }"
    try source.write(to: file, atomically: true, encoding: .utf8)
    _ = try await storage.cache.collect(at: file.path)
    let decoded = try await storage.cache.collect(at: file.path)
    #expect(!decoded.sourceBuffer.hasLoadedSnapshot)

    if removed {
      try FileManager.default.removeItem(at: file)
    } else {
      try "struct Changed {}".write(
        to: file, atomically: true, encoding: .utf8
      )
    }

    #expect(try decoded.source.text == source)
    #expect(try decoded.structs[0].nameSource.text == "Store")
    #expect(try decoded.functions[0].bodySource.text == " fetch(value: 1) ")
    #expect(try decoded.calls[0].arguments[0].labelSource?.text == "value")
    #expect(try decoded.calls[0].arguments[0].source.text == "1")
  }
}
