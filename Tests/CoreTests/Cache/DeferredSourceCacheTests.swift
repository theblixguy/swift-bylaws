import Foundation
import Testing
@testable import BylawsCore
@testable import BylawsSemantics

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

    let name = try decoded.structs[0].nameSource
    #expect(name.text == "Store")
    #expect(name.snapshot.parsedTree == nil)
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
    encoder.encode(Range<Int>?.none)
    let decoder = try CacheDecoder(encoder.bytes, path: "/virtual/App.swift")
    decoder.bindSource(to: .v6)

    #expect(throws: CacheDecoder.Malformed.self) {
      try ParsedSource(from: decoder)
    }
    #expect(!decoder.source.hasLoadedSnapshot)
  }

  @Test(
    "Cache rejects name ranges outside declaration or scalar boundaries",
    arguments: [0..<3, 18..<23, 4..<14, 7..<8, 8..<9, -1..<4, 4..<999, 4..<4]
  )
  func rejectsMalformedNameRanges(nameRange: Range<Int>) throws {
    let encoder = CacheEncoder()
    encoder.encode("let café = 1\nlet other = 2")
    encoder.encode(4..<13)
    encoder.encode(Optional(nameRange))
    let decoder = try CacheDecoder(encoder.bytes, path: "/virtual/App.swift")
    decoder.bindSource(to: .v6)

    #expect(throws: CacheDecoder.Malformed.self) {
      try ParsedSource(from: decoder)
    }
    #expect(!decoder.source.hasLoadedSnapshot)
  }

  @Test("Cached names and callees retain exact source without syntax")
  func capturedNames() throws {
    let original = try FileCollector.collect(
      source: """
      import Feature.Storage
      struct Café {
        var `repeat` = 1
        func load() { engine.`send`(value: 1); #inspect(2) }
      }
      """, path: "/virtual/Café.swift"
    )
    let encoder = CacheEncoder()
    encoder.encode(original)
    let decoder = try CacheDecoder(encoder.bytes, path: original.path)
    let decoded = try SourceFile(from: decoder)
    let names = try [
      decoded.imports.only().nameSource,
      decoded.structs.only().nameSource,
      decoded.properties.only().nameSource,
      decoded.functions.only().nameSource,
    ] + decoded.calls.map { try $0.calledExpressionSource }

    #expect(decoder.isAtEnd)
    #expect(names.map(\.text) == [
      "Feature.Storage", "Café", "`repeat`", "load", "engine.`send`",
      "#inspect",
    ])
    #expect(names.allSatisfy { $0.snapshot.parsedTree == nil })
    let renamed = try decoded.properties.only().nameSource
      .replacement(with: "value")
    #expect(try renamed.source.file.replacement(applying: [renamed])
      .replacement == """
      import Feature.Storage
      struct Café {
        var value = 1
        func load() { engine.`send`(value: 1); #inspect(2) }
      }
      """)
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
