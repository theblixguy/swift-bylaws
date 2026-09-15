import BylawsSemantics
import Testing

@Suite("Structured source expressions")
struct ExpressionCollectionTests {
  @Test(
    "String literals decode escapes without evaluating expressions",
    arguments: [
      (
        source: #""https:\u{2f}\u{2f}example.com""#,
        value: "https://example.com"
      ),
      (source: ##"#"https://example.com"#"##, value: "https://example.com"),
      (
        source: "\"\"\"\nhttps://example.com\n\"\"\"",
        value: "https://example.com"
      ),
    ]
  )
  func strings(source: String, value: String) throws {
    let expression = try argument(source)
    #expect(expression.stringValue == value)
  }

  @Test("Literal access distinguishes false and zero from unknown values")
  func literalValues() throws {
    #expect(try argument("false").booleanValue == false)
    #expect(try argument("0").integerValue == 0)
    #expect(try argument("0xff").integerValue == 255)
    #expect(try argument("1.5").floatingPointValue == 1.5)
    #expect(try argument("nil").isNilLiteral)
    #expect(try argument("flag").booleanValue == nil)
    #expect(try argument("1 + 2").integerValue == nil)
  }

  @Test("Interpolation separates privacy arguments from string contents")
  func privacy() throws {
    let expression =
      try argument(#""User: \(user, privacy: .public), literal .private""#)
    #expect(expression.stringValue == nil)
    let interpolation = try #require(expression.interpolations.first)
    #expect(interpolation.map(\.label) == [nil, "privacy"])
    #expect(interpolation.map(\.expression.referenceName) == ["user", "public"])
    #expect(try argument(#""privacy: .public""#).interpolations.isEmpty)
  }

  @Test("Dictionary entries preserve repeated keys and structured values")
  func dictionary() throws {
    let expression = try argument("[key: .first, key: [false, value]]")
    let entries = try #require(expression.dictionaryElements)
    #expect(entries.map(\.key.referenceName) == ["key", "key"])
    #expect(entries.first?.value.referenceName == "first")
    let array = try #require(entries.last?.value.arrayElements)
    #expect(array.first?.booleanValue == false)
    #expect(array.last?.referenceName == "value")
    #expect(try argument("[:]").dictionaryElements == [])
    #expect(try argument("[]").arrayElements == [])
    #expect(try argument("unknown").arrayElements == nil)
  }

  @Test("Nested expressions keep UTF-8 source positions")
  func positions() throws {
    let file = try FileCollector.collect(
      source: "func run() { log(\"é\", value: [\n  .public\n]) }",
      path: "/virtual/App.swift"
    )
    let call = try #require(file.calls.first)
    let expression = try #require(call.arguments.last?.expression)
    let member = try #require(expression.arrayElements?.first)
    #expect(member.location.filePath == "/virtual/App.swift")
    #expect(member.location.line == 2)
    #expect(member.location.column == 3)
    #expect(member.location.utf8Offset == 34)
  }

  private func argument(_ source: String) throws -> SourceExpression {
    let file = try FileCollector.collect(
      source: "func run() { check(\(source)) }",
      path: "/virtual/Expressions.swift"
    )
    return try #require(file.calls.first?.arguments.first?.expression)
  }

  @Test("References locate identifier tokens", arguments: [
    (text: "save", column: 1),
    (text: ".save", column: 2),
    (text: "store.save", column: 7),
    (text: "é.save", column: 4),
    (text: "save(_:)", column: 1),
    (text: "store.`save`", column: 7),
  ])
  func referencePositions(text: String, column: Int) throws {
    let expression = try argument(text)
    let location = try #require(expression.referenceLocation)
    #expect(location.filePath == expression.location.filePath)
    #expect(location.line == expression.location.line)
    #expect(location.column == expression.location.column + column - 1)
    #expect(location.utf8Offset == expression.location.utf8Offset.map {
      $0 + column - 1
    })
  }

  @Test("Multiline member references retain file and argument positions")
  func multilineReference() throws {
    let source = "func run() { use(\"é\", store\n  .save) }"
    let file = try FileCollector.collect(
      source: source,
      path: "/virtual/App.swift"
    )
    let expression = try #require(file.expressions
      .first { $0.referenceName == "save" })
    let argument = try #require(file.calls.first?.arguments.last?.expression)
    #expect(expression.referenceLocation == argument.referenceLocation)
    #expect(expression.referenceLocation?.line == 2)
    #expect(expression.referenceLocation?.column == 4)
    #expect(expression.referenceLocation?.utf8Offset == 32)
  }

  @Test("Non-reference expressions have no identifier location", arguments: [
    "42", "\"text\"", "[value]", "save()", "first + second",
  ])
  func nonReferences(text: String) throws {
    #expect(try argument(text).referenceLocation == nil)
  }

  @Test("Argument inspection preserves Swift language mode")
  func languageMode() throws {
    let file = try FileCollector.collect(
      source: """
      func run() {
        check({
          @available (swift, obsoleted: 1.0)
          func legacy() {}
        })
      }
      """,
      path: "/virtual/Legacy.swift", swiftLanguageMode: .v5
    )
    #expect(file.calls.first?.arguments.first?.expression != nil)
  }

  @Test("File expressions include local bodies and every compilation branch")
  func fileExpressions() throws {
    let file = try FileCollector.collect(
      source: """
      let global = Settings.public
      func outer() {
        func local() { use(.public) }
        let action = { use(.private) }
      }
      #if false
      let other = .public
      #endif
      """,
      path: "/virtual/Expressions.swift"
    )
    let references = file.expressions.filter { $0.referenceName == "public" }
    #expect(references.map(\.text) == ["Settings.public", ".public", ".public"])
    #expect(references.map(\.location.line) == [1, 3, 7])
    #expect(file.expressions
      .count(where: { $0.referenceName == "private" }) == 1)
  }

  @Test("Unlocated arguments and malformed text have no expression")
  func unavailableExpression() {
    #expect(FunctionCall.Argument(label: nil, text: "true").expression == nil)
    let location = DeclarationLocation(
      filePath: "/virtual/Call.swift",
      line: 1,
      column: 1
    )
    #expect(FunctionCall.Argument(
      label: nil,
      text: "value +",
      location: location
    ).expression == nil)
    #expect(FunctionCall.Argument(
      label: nil,
      text: "first(); second()",
      location: location
    ).expression == nil)
  }
}
