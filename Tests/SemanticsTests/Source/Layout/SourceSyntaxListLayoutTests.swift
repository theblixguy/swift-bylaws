import BylawsSemantics
import Testing

@Suite("Syntax list layouts")
struct SourceSyntaxListLayoutTests {
  @Test("Canonical lists retain elements and separators", arguments: [
    (
      SourceNode.Kind.conditionList,
      "if zebra, apple {}",
      "if apple, zebra {}"
    ),
    (
      .genericParameterList,
      "func pick<Zebra, Apple>() {}",
      "func pick<Apple, Zebra>() {}"
    ),
    (
      .genericArgumentList,
      "let value: Pair<Zebra, Apple>",
      "let value: Pair<Apple, Zebra>"
    ),
    (
      .genericRequirementList,
      "func pick<A, Z>() where Z: Second, A: First {}",
      "func pick<A, Z>() where A: First, Z: Second {}"
    ),
    (
      .inheritedTypeList,
      "struct Value: Zebra, Apple {}",
      "struct Value: Apple, Zebra {}"
    ),
    (
      .expressionList,
      "let pair = (zebra: 1, apple: 2)",
      "let pair = (apple: 2, zebra: 1)"
    ),
    (
      .tupleTypeElementList,
      "let pair: (zebra: Int, apple: String)",
      "let pair: (apple: String, zebra: Int)"
    ),
    (
      .tuplePatternElementList,
      "let (zebra, apple) = pair",
      "let (apple, zebra) = pair"
    ),
    (
      .closureParameterList,
      "let run = { (zebra: Int, apple: String) in consume() }",
      "let run = { (apple: String, zebra: Int) in consume() }"
    ),
    (
      .closureCaptureList,
      "let run = { [zebra, apple] in consume() }",
      "let run = { [apple, zebra] in consume() }"
    ),
    (
      .closureShorthandParameterList,
      "let run = { zebra, apple in consume() }",
      "let run = { apple, zebra in consume() }"
    ),
    (
      .enumCaseParameterList,
      "enum Value { case pair(zebra: Int, apple: String) }",
      "enum Value { case pair(apple: String, zebra: Int) }"
    ),
    (
      .primaryAssociatedTypeList,
      "protocol Value<Zebra, Apple> {}",
      "protocol Value<Apple, Zebra> {}"
    ),
    (
      .accessorList,
      "var value: Int {\n  set { save(newValue) }\n  get { load() }\n}",
      "var value: Int {\n  get { load() }\n  set { save(newValue) }\n}"
    ),
    (
      .switchCaseList,
      "switch value {\ncase .zebra: first()\ncase .apple: second()\n}",
      "switch value {\ncase .apple: second()\ncase .zebra: first()\n}"
    ),
    (
      .switchCaseItemList,
      "switch value { case .zebra, .apple: consume() }",
      "switch value { case .apple, .zebra: consume() }"
    ),
  ])
  func canonicalLists(
    kind: SourceNode.Kind,
    source: String,
    expected: String
  ) throws {
    let file = try collect(source)
    let list = try #require(file.syntaxNodes(of: kind).first)
    let elements = list.elements
    try #require(elements.count == 2)
    #expect(list.children == elements)
    #expect(file.syntaxNodes(of: .syntaxElement).filter {
      $0.parent == list
    } == elements)
    let edit = try elements.replacement {
      elements.sorted { $0.text < $1.text }
    }

    #expect(applying(edit) == expected)

    let corrected = try collect(expected)
    let correctedElements = try #require(corrected.syntaxNodes(of: kind).first)
      .elements
    let repeated = try correctedElements.replacement {
      correctedElements.sorted { $0.text < $1.text }
    }
    #expect(applying(repeated) == expected)
  }

  @Test("Generic clauses support multiline layout", arguments: [
    (
      SourceNode.Kind.genericParameterList,
      "func pick<First, Second>() {}",
      "func pick<\n  First,\n  Second\n>() {}"
    ),
    (
      .genericArgumentList,
      "let value: Pair<First, Second>",
      "let value: Pair<\n  First,\n  Second\n>"
    ),
    (
      .tupleTypeElementList,
      "let value: (first: Int, second: Int)",
      "let value: (\n  first: Int,\n  second: Int\n)"
    ),
    (
      .closureCaptureList,
      "let run = { [first, second] in consume() }",
      "let run = { [\n  first,\n  second\n] in consume() }"
    ),
  ])
  func multilineLists(
    kind: SourceNode.Kind,
    source: String,
    expected: String
  ) throws {
    let file = try collect(source)
    let elements = try #require(file.syntaxNodes(of: kind).first).elements
    let edit = try elements.replacement {
      for element in elements { Line { element } }
    }

    #expect(applying(edit) == expected)
  }

  @Test("Incomplete and repeated list elements stop replacement")
  func inventory() throws {
    let file = try collect("if first, second {}")
    let elements = try #require(file.syntaxNodes(of: .conditionList).first)
      .elements

    #expect(throws: SourceLayoutReplacementError.noncontiguousElements) {
      try elements.prefix(1).replacement { elements[0] }
    }
    #expect(throws: SourceLayoutReplacementError.missingElement) {
      try elements.replacement { elements[0] }
    }
    #expect(throws: SourceLayoutReplacementError.repeatedElement) {
      try elements.replacement {
        elements
        elements[0]
      }
    }
  }

  @Test("Elements from neighbouring lists stop replacement")
  func neighbouringLists() throws {
    let file = try collect("if first, second {}\nif third, fourth {}")
    let lists = file.syntaxNodes(of: .conditionList)
    try #require(lists.count == 2)
    let first = lists[0].elements
    let second = lists[1].elements

    #expect(throws: SourceLayoutReplacementError.foreignElement) {
      try first.replacement { second }
    }
    #expect(throws: SourceLayoutReplacementError.noncontiguousElements) {
      try [first[0], second[1]].replacement {
        first[0]
        second[1]
      }
    }
  }

  @Test("Comma-inclusive nested edits stop layout replacement")
  func commaOwningEdit() throws {
    let file = try collect("if first, second {}")
    let elements = try #require(file.syntaxNodes(of: .conditionList).first)
      .elements
    let first = try elements[0].source
    try #require(first.text == "first,")

    #expect(throws: SourceLayoutReplacementError.foreignElement) {
      try elements.replacement {
        first.replacement(with: "third,")
        elements[1]
      }
    }
  }

  @Test("Inline comments stop list rearrangement", arguments: [
    (
      SourceNode.Kind.genericParameterList,
      "func pick<First, /* Keep */ Second>() {}"
    ),
    (.conditionList, "if first, /* Keep */ second {}"),
    (
      .closureCaptureList,
      "let run = { [first, /* Keep */ second] in consume() }"
    ),
  ])
  func ambiguousComments(kind: SourceNode.Kind, source: String) throws {
    let file = try collect(source)
    let elements = try #require(file.syntaxNodes(of: kind).first).elements

    #expect(throws: SourceLayoutReplacementError.ambiguousTrivia) {
      try elements.replacement { elements.reversed() }
    }
  }

  @Test("Conditional switch cases stop rearrangement")
  func conditionalCases() throws {
    let file = try collect(
      """
      switch value {
      #if DEBUG
      case .first: consume()
      #endif
      case .second: consume()
      }
      """
    )
    let elements = try #require(file.syntaxNodes(of: .switchCaseList).first)
      .elements

    #expect(throws: SourceLayoutReplacementError.conditionalCompilation) {
      try elements.replacement { elements }
    }
  }

  @Test(
    "List projection keeps fallback kinds without treating declarations as lists"
  )
  func elementKinds() throws {
    let file = try collect("func run<First, Second>() {}")
    let declaration = try #require(file.syntaxNodes(of: .functionDeclaration)
      .first)
    let list = try #require(file.syntaxNodes(of: .genericParameterList).first)

    #expect(declaration.elements.isEmpty)
    #expect(list.elements.map(\.kind) == [.syntaxElement, .syntaxElement])
    #expect(list.elements.map(\.text) == ["First,", "Second"])
    #expect(try list.elements[0].source.file
      .text == "func run<First, Second>() {}")
  }

  private func collect(_ source: String) throws -> SourceFile {
    try FileCollector.collect(source: source, path: "/virtual/List.swift")
  }

  private func applying(_ edit: SourceFix.Edit) -> String {
    var bytes = Array(edit.source.file.text.utf8)
    bytes.replaceSubrange(edit.source.range, with: edit.replacement.utf8)
    return String(decoding: bytes, as: UTF8.self)
  }
}
