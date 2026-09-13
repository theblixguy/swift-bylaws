import BylawsSemantics
import Testing

@Suite("Source metadata collection")
struct SourceMetadataCollectionTests {
  @Test("Collector records documentation comments")
  func extractsDocumentation() throws {
    let file = try FileCollector.collect(
      source: """
      /// A documented type.
      public struct Order {
        /// Places the order.
        public func place() {}

        public func cancel() {}
      }
      """,
      path: "/virtual/App/Order.swift"
    )

    let order = try #require(file.structs.first)
    #expect(order.isDocumented)
    #expect(order.documentation == "/// A documented type.")

    let place = try #require(file.functions.first { $0.name == "place" })
    #expect(place.isDocumented)

    let cancel = try #require(file.functions.first { $0.name == "cancel" })
    #expect(!cancel.isDocumented)
  }

  @Test("Collector records type aliases")
  func extractsTypealiases() throws {
    let file = try FileCollector.collect(
      source: """
      struct Outer {
        typealias Completion = (Result<String, Error>) -> Void
      }
      public typealias Identifier = String
      """,
      path: "/virtual/App/Aliases.swift"
    )

    let completion = try #require(
      file.typealiases.first { $0.name == "Completion" }
    )
    #expect(completion.aliasedTypeName == "(Result<String, Error>) -> Void")
    #expect(completion.enclosingTypeName == "Outer")

    let identifier = try #require(
      file.typealiases.first { $0.name == "Identifier" }
    )
    #expect(identifier.isPublic)
  }

  @Test("Collector records source and function line counts")
  func extractsLineCounts() throws {
    let file = try FileCollector.collect(
      source: """
      func short() {
        let value = 1
        _ = value
      }
      """,
      path: "/virtual/App/Short.swift"
    )

    #expect(file.lineCount == 4)
    let short = try #require(file.functions.first)
    #expect(short.bodyLineCount == 4)
  }

  @Test(
    "Line counts use every Swift line ending",
    arguments: ["\n", "\r\n", "\r"]
  )
  func lineCountsUseSwiftLineEndings(_ newline: String) throws {
    let source = ["struct One {}", "struct Two {}", ""].joined(
      separator: newline
    )
    let file = try FileCollector.collect(
      source: source,
      path: "/virtual/App/Lines.swift"
    )

    #expect(file.lineCount == 3)
    #expect(file.structs.map(\.location.line) == [1, 2])
  }
}
