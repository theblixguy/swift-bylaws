import BylawsSemantics
import Testing

@Suite("Captured list removal")
struct SourceListRemovalTests {
  @Test("Removal retains formatting directive errors", arguments: [false, true])
  func formattingDirective(builder: Bool) throws {
    let file = try FileCollector.collect(
      source: "send(value: /* swiftformat:disable */ 1)",
      path: "/virtual/Calls.swift"
    )
    let list = try #require(file.syntaxNodes(of: .functionCall).first?.call)
      .argumentList
    let argument = try #require(list.first)

    #expect(throws: SourceLayoutReplacementError.ambiguousTrivia) {
      if builder { try Remove(argument).correction }
      else { try list.removing(argument) }
    }
  }

  @Test(
    "Removal retains conditional compilation errors",
    arguments: [false, true]
  )
  func conditionalCompilation(builder: Bool) throws {
    let file = try FileCollector.collect(
      source: "func run() {\n#if ENABLED\nwork()\n#endif\n}",
      path: "/virtual/Conditions.swift"
    )
    let list = try #require(file.syntaxNodes(of: .codeBlock).first)
      .statementList
    let statement = try #require(list.first)

    #expect(throws: SourceLayoutReplacementError.conditionalCompilation) {
      if builder { try Remove(statement).correction }
      else { try list.removing(statement) }
    }
  }

  @Test("Equal captured snapshots resolve elements in the list's syntax tree")
  func equalSnapshots() throws {
    let first = try FileCollector.collect(
      source: "send(first: 1, last: 2)",
      path: "/virtual/Calls.swift"
    )
    let second = try FileCollector.collect(
      source: "send(first: 1, last: 2)",
      path: first.path
    )
    let list = try #require(first.syntaxNodes(of: .functionCall).first?.call)
      .argumentList
    let argument = try #require(second.syntaxNodes(of: .functionCall).first?
      .call?.arguments.first)
    let correction = try list.removing(argument)

    #expect(try applying(correction, to: first) == "send(last: 2)")
  }

  @Test("Argument removal retains labels and separators", arguments: [
    ("send(first: 1, second: 1)", 0, "send(second: 1)"),
    ("send(first: 1, middle: 2, last: 3)", 1, "send(first: 1, last: 3)"),
    ("send(first: 1, second: 2)", 1, "send(first: 1)"),
    ("send(first: 1, second: 2,)", 1, "send(first: 1,)"),
    ("send(value: 1)", 0, "send()"),
    ("send(value: 1,)", 0, "send()"),
  ])
  func argumentSeparators(input: String, index: Int, expected: String) throws {
    let file = try FileCollector.collect(
      source: input,
      path: "/virtual/Calls.swift"
    )
    let call = try #require(file.syntaxNodes(of: .functionCall)
      .compactMap(\.call).first)
    let removal = try Remove(call.arguments[index])

    #expect(try applying(removal.correction, to: file) == expected)
  }

  @Test("Multiline removal preserves remaining argument indentation")
  func multilineArgument() throws {
    let file = try FileCollector.collect(
      source: "send(\n  first: 1,\n  second: 2\n)", path: "/virtual/Calls.swift"
    )
    let call = try #require(file.syntaxNodes(of: .functionCall)
      .compactMap(\.call).first)
    let correction = try call.argumentList.removing(call.arguments[0])

    #expect(try applying(correction, to: file) == "send(\n  second: 2\n)")
  }

  @Test("Declaration removal handles sole attribute and modifier")
  func declarationLists() throws {
    let file = try FileCollector.collect(
      source: "@MainActor final class Store {}", path: "/virtual/Store.swift"
    )
    let declaration = try #require(file.classes.first)
    let attribute = try Remove(#require(declaration.attributes.first))
    let modifier = try Remove(#require(declaration.modifierList.first))

    #expect(try applying(attribute.correction, to: file) ==
      "final class Store {}")
    #expect(try applying(modifier.correction, to: file) ==
      "@MainActor class Store {}")
  }

  @Test("Sole member removal retains enclosing declaration")
  func soleMember() throws {
    let file = try FileCollector.collect(
      source: "struct Store {\n  let count = 1\n}", path: "/virtual/Store.swift"
    )
    let declaration = try #require(file.syntaxNodes(of: .structDeclaration)
      .first)
    let member = try #require(declaration.members.first)
    let correction = try declaration.memberList.removing(member)

    #expect(try applying(correction, to: file) == "struct Store {\n}")
  }

  @Test(
    "Removal preserves comments belonging to adjacent elements",
    arguments: [
      "send(first: 1, /* keep */ second: 2)",
      "send(first: 1 /* keep */, second: 2)",
    ]
  )
  func commentOwnership(_ input: String) throws {
    let file = try FileCollector.collect(
      source: input,
      path: "/virtual/Calls.swift"
    )
    let call = try #require(file.syntaxNodes(of: .functionCall)
      .compactMap(\.call).first)
    let correction = try call.argumentList.removing(call.arguments[0])

    #expect(correction.outcome == .violation)
    #expect(correction.fix == nil)
    #expect(correction.reason != nil)
  }

  @Test("Removal rejects an element from another captured file")
  func differentFile() throws {
    let first = try FileCollector.collect(
      source: "send(1)",
      path: "/virtual/First.swift"
    )
    let second = try FileCollector.collect(
      source: "send(1)",
      path: "/virtual/Second.swift"
    )
    let firstCall = try #require(first.syntaxNodes(of: .functionCall)
      .compactMap(\.call).first)
    let secondArgument = try #require(second.syntaxNodes(of: .functionCall)
      .compactMap(\.call).first?.arguments.first)

    #expect(throws: SourceError.differentSnapshots) {
      try firstCall.argumentList.removing(secondArgument)
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
