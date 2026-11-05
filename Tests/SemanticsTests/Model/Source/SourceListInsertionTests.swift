import BylawsSemantics
import Testing

@Suite("Captured list insertion")
struct SourceListInsertionTests {
  @Test("Empty argument lists retain insertion position", arguments: [
    ("send()", "send(value: 1)"),
    ("send( )", "send(value: 1)"),
    ("send { work() }", "send(value: 1) { work() }"),
  ])
  func emptyArguments(input: String, expected: String) throws {
    let file = try FileCollector.collect(
      source: input,
      path: "/virtual/Calls.swift"
    )
    let call = try #require(file.syntaxNodes(of: .functionCall)
      .compactMap(\.call).first { $0.calledExpression == "send" })
    let list = try call.argumentList

    #expect(list.isEmpty)
    let insertion = try Insert("value: 1", into: list)

    #expect(try applying(insertion.correction, to: file) == expected)
  }

  @Test("Argument insertion preserves separators", arguments: [
    (
      "send(second: 2)",
      SourceListPosition.start,
      "first: 1",
      "send(first: 1, second: 2)"
    ),
    (
      "send(first: 1, last: 3)",
      .index(1),
      "middle: 2",
      "send(first: 1, middle: 2, last: 3)"
    ),
    ("send(first: 1)", .end, "second: 2", "send(first: 1, second: 2)"),
    ("send(first: 1,)", .end, "second: 2", "send(first: 1, second: 2,)"),
  ])
  func argumentSeparators(
    input: String, position: SourceListPosition, inserted: String,
    expected: String
  ) throws {
    let file = try FileCollector.collect(
      source: input,
      path: "/virtual/Calls.swift"
    )
    let call = try #require(file.syntaxNodes(of: .functionCall)
      .compactMap(\.call).first)
    let correction = try call.argumentList.inserting(inserted, at: position)

    #expect(try applying(correction, to: file) == expected)
  }

  @Test("Nested argument insertion targets captured call after Unicode")
  func nestedCall() throws {
    let file = try FileCollector.collect(
      source: "let café = outer(inner(), other())", path: "/virtual/Calls.swift"
    )
    let inner = try #require(file.syntaxNodes(of: .functionCall)
      .compactMap(\.call)
      .first { $0.calledExpression == "inner" })
    let correction = try inner.argumentList.inserting("key: \"🦊\"")

    #expect(try applying(correction, to: file) ==
      "let café = outer(inner(key: \"🦊\"), other())")
  }

  @Test("Multiline argument insertion preserves indentation and line endings")
  func multilineArguments() throws {
    let file = try FileCollector.collect(
      source: "func run() {\r\n\tsend(\r\n\t\tfirst: 1\r\n\t)\r\n}",
      path: "/virtual/Calls.swift"
    )
    let call = try #require(file.syntaxNodes(of: .functionCall)
      .compactMap(\.call).first)
    let correction = try call.argumentList.inserting("second: 2")

    #expect(try applying(correction, to: file)
      ==
      "func run() {\r\n\tsend(\r\n\t\tfirst: 1,\r\n\t\tsecond: 2\r\n\t)\r\n}")
  }

  @Test("Empty declaration lists support attributes and modifiers")
  func declarationLists() throws {
    let file = try FileCollector.collect(
      source: "class Store {}",
      path: "/virtual/Store.swift"
    )
    let declaration = try #require(file.classes.first)
    let attribute = try Insert("@MainActor", into: declaration.attributeList)
    let modifier = try Insert("final", into: declaration.modifierList)

    #expect(try applying(attribute.correction, to: file) ==
      "@MainActor class Store {}")
    #expect(try applying(modifier.correction, to: file) ==
      "final class Store {}")
  }

  @Test("Declaration insertion retains existing attributes and modifiers")
  func populatedDeclarationLists() throws {
    let file = try FileCollector.collect(
      source: "@MainActor public class Store {}", path: "/virtual/Store.swift"
    )
    let declaration = try #require(file.classes.first)
    let attribute = try declaration.attributeList.inserting(
      "@Observable",
      at: .start
    )
    let modifier = try declaration.modifierList.inserting("final")

    #expect(try applying(attribute, to: file) ==
      "@Observable @MainActor public class Store {}")
    #expect(try applying(modifier, to: file) ==
      "@MainActor public final class Store {}")
  }

  @Test("Empty member list creates indented declaration")
  func emptyMembers() throws {
    let file = try FileCollector.collect(
      source: "struct Store {}",
      path: "/virtual/Store.swift"
    )
    let declaration = try #require(file.syntaxNodes(of: .structDeclaration)
      .first)
    let correction = try declaration.memberList.inserting("let count = 1")

    #expect(try applying(correction, to: file) ==
      "struct Store {\n  let count = 1\n}")
  }

  @Test("Empty statement list retains closure signature")
  func emptyStatements() throws {
    let file = try FileCollector.collect(
      source: "let callback = { value in }", path: "/virtual/Callbacks.swift"
    )
    let closure = try #require(file.syntaxNodes(of: .closureExpression).first)
    let correction = try closure.statementList.inserting("consume(value)")

    #expect(try applying(correction, to: file) ==
      "let callback = { value in\n  consume(value)\n}")
  }

  @Test("Insertion preserves comments at empty list boundary")
  func commentBoundary() throws {
    let file = try FileCollector.collect(
      source: "send(/* keep */)",
      path: "/virtual/Calls.swift"
    )
    let call = try #require(file.syntaxNodes(of: .functionCall)
      .compactMap(\.call).first)
    let correction = try call.argumentList.inserting("value: 1")

    #expect(correction.outcome == .violation)
    #expect(correction.fix == nil)
    #expect(correction.reason != nil)
  }

  @Test("Insertion takes one complete argument", arguments: [
    "first: 1, second: 2", "value: )", "value: 1,", "value: 1)\nother(",
  ])
  func rejectsMultipleElements(_ inserted: String) throws {
    let file = try FileCollector.collect(
      source: "send()",
      path: "/virtual/Calls.swift"
    )
    let call = try #require(file.syntaxNodes(of: .functionCall)
      .compactMap(\.call).first)
    let correction = try call.argumentList.inserting(inserted)

    #expect(correction.outcome == .violation)
    #expect(correction.fix == nil)
  }

  @Test("Insertion rejects index outside captured list")
  func insertionBounds() throws {
    let file = try FileCollector.collect(
      source: "send()",
      path: "/virtual/Calls.swift"
    )
    let call = try #require(file.syntaxNodes(of: .functionCall)
      .compactMap(\.call).first)

    #expect(throws: SourceError.rangeOutOfBounds) {
      try call.argumentList.inserting("1", at: .index(1))
    }
  }

  private func applying(
    _ correction: SourceCorrection,
    to file: SourceFile
  ) throws -> String {
    let fix = try #require(correction.fix)
    return try file.source.replacement(applying: fix.edits).replacement
  }
}
