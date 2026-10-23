import BylawsSemantics
import Foundation
import Testing
@testable import BylawsCore

@Suite("Cached source projections")
struct SourceProjectionCacheTests {
  @Test("Binary cache retains exact correction spans")
  func retainsProjections() throws {
    let original = try FileCollector.collect(
      source: """
      import Foundation
      struct Café {
        var value = 1
        func read() { run(label: "🦊", other: "🦊") }
        init() { value = 2 }
      }
      protocol Reader { func read() }
      extension Café {}
      typealias Name = String
      enum Kind { case first }
      """, path: "/virtual/App.swift"
    )
    let decoded = try roundTrip(original, at: original.path)
    #expect(try decoded.source == original.source)
    #expect(try decoded.structs[0].source == original.structs[0].source)
    #expect(try decoded.structs[0].nameSource.text == "Café")
    #expect(try decoded.properties[0].source == original.properties[0].source)
    #expect(try decoded.functions[0].bodySource == original.functions[0]
      .bodySource)
    #expect(try decoded.initializers[0].bodySource == original.initializers[0]
      .bodySource)
    #expect(try decoded.protocols[0].source == original.protocols[0].source)
    #expect(try decoded.protocols[0].requiredFunctions[0].source
      == original.protocols[0].requiredFunctions[0].source)
    #expect(try decoded.extensions[0].source == original.extensions[0].source)
    #expect(try decoded.imports[0].source == original.imports[0].source)
    #expect(try decoded.typealiases[0].source == original.typealiases[0].source)
    #expect(try decoded.enums[0].cases[0].source == original.enums[0].cases[0]
      .source)
    let call = try #require(decoded.calls.first)
    #expect(try call.memberNameSource.text == "run")
    #expect(try call.calledExpressionSource.text == "run")
    let argument = try call.argument(labeled: "other")
    #expect(try argument.labelSource?.text == "other")
    #expect(try argument.expressionSource == original.calls[0].arguments[1]
      .expressionSource)
    #expect(try argument.expression?.source == argument.source)
  }

  @Test("Cache rebinding changes projection paths without changing bytes")
  func portablePaths() throws {
    let original = try FileCollector.collect(
      source: "struct Store {}", path: "/before/Store.swift"
    )
    let moved = try roundTrip(original, at: "/after/Store.swift")
    #expect(try moved.source.filePath == "/after/Store.swift")
    #expect(try moved.structs[0].nameSource.filePath == "/after/Store.swift")
    #expect(try moved.structs[0].source.text == original.structs[0].source.text)
  }

  @Test("Cache rejects projection ranges inside UTF-8 scalars")
  func rejectsMalformedSpans() throws {
    let file = try FileCollector.collect(
      source: "//🦊", path: "/virtual/App.swift"
    )
    let encoder = CacheEncoder()
    encoder.encode(file.sourceText)
    encoder.encode(2..<3)
    let decoder = try CacheDecoder(encoder.bytes, path: file.path)
    decoder.bindSource(to: .v6)
    #expect(throws: CacheDecoder.Malformed.self) {
      try SourceSlice(from: decoder)
    }
  }

  @Test("Cached attributes retain layout source at the current path")
  func attributeLayouts() throws {
    let original = try FileCollector.collect(
      source: "@MainActor\n@Observable class Screen {}",
      path: "/before/Screen.swift"
    )
    let moved = try roundTrip(original, at: "/after/Screen.swift")
    let attributes = try #require(moved.classes.first).attributes
    let edit = try attributes.replacement {
      Line { attributes.sorted { $0.name > $1.name } }
    }

    #expect(edit.source.filePath == "/after/Screen.swift")
    #expect(edit.source.text == "@MainActor\n@Observable ")
    #expect(edit.replacement == "@Observable @MainActor\n")
    #expect(try #require(attributes.first).source.file == moved.source)
  }

  @Test("Public decoding retains model identity without source authority")
  func publicDecoding() throws {
    let original = try FileCollector.collect(
      source: "import Foundation", path: "/virtual/App.swift"
    )
    let cached = try roundTrip(original, at: original.path)
    let decoded = try JSONDecoder().decode(
      Import.self, from: JSONEncoder().encode(cached.imports[0])
    )
    #expect(decoded == original.imports[0])
    #expect(throws: SourceError.unavailable) { _ = try decoded.source }
  }

  private func roundTrip(
    _ file: SourceFile,
    at path: String
  ) throws -> SourceFile {
    let encoder = CacheEncoder()
    encoder.encode(file)
    let decoder = try CacheDecoder(encoder.bytes, path: path)
    let decoded = try SourceFile(from: decoder)
    #expect(decoder.isAtEnd)
    return decoded
  }
}
