import BylawsSemantics
import Foundation
import Testing

@Suite("Captured list correction composition")
struct SourceListCompositionTests {
  @Test("Property and declaration views share list ownership")
  func propertyAlias() throws {
    let file = try collect("struct Store { var count = 0 }")
    let declaration = try #require(
      file.syntaxNodes(of: .variableDeclaration)
        .first
    )
    let property = try #require(declaration.property)
    let fromProperty = try property.modifierList.inserting("private")
    let fromDeclaration = try declaration.modifierList.inserting("private")

    #expect(
      try applying([fromProperty, fromDeclaration], to: file)
        == "struct Store { private var count = 0 }"
    )
  }

  @Test("Indented modifier layout composes insertion")
  func indentedModifiers() throws {
    let file = try collect("struct Outer {\n  public class Store {}\n}")
    let declaration = try #require(file.classes.first)
    let list = try declaration.modifierList
    let layout = try Layout(list) { list }.correction
    let insertion = try list.inserting("final")

    let corrected = try applying([layout, insertion], to: file)
    #expect(corrected == "struct Outer {\n  public final class Store {}\n}")
  }

  @Test("Combined insertions retain an existing comment gap")
  func commentGap() throws {
    let file = try collect("send(first: 1, // keep\n  second: 2)")
    let list = try #require(
      file.syntaxNodes(of: .functionCall)
        .compactMap(\.call).first
    ).argumentList
    let middle = try list.inserting("middle: 3", at: .index(1))
    let last = try list.inserting("last: 4")

    #expect(
      try applying([middle, last], to: file)
        == "send(first: 1, // keep\n  middle: 3,\n  second: 2,\n  last: 4)"
    )
  }

  @Test(
    "Attribute and modifier insertions share declaration position",
    arguments: [false, true]
  )
  func declarationPrefix(reversed: Bool) throws {
    let file = try collect("class Store {}")
    let declaration = try #require(file.classes.first)
    let attribute = try Insert("@MainActor", into: declaration.attributeList)
      .correction
    let modifier = try Insert("final", into: declaration.modifierList)
      .correction
    let operations = reversed ? [modifier, attribute] : [attribute, modifier]

    #expect(try applying(operations, to: file) ==
      "@MainActor final class Store {}")
  }

  @Test(
    "Layout and insertion compose in either builder order",
    arguments: [false, true]
  )
  func formattedInsertion(reversed: Bool) throws {
    let file = try collect("send(first: 1, last: 3)")
    let call = try #require(
      file.syntaxNodes(of: .functionCall)
        .compactMap(\.call).first
    )
    let list = try call.argumentList
    let layout = try Layout(list) {
      Newline()
      Lines { list }
      Newline()
    }.correction
    let insertion = try Insert("middle: 2", into: list, at: .index(1))
      .correction
    let operations = reversed ? [insertion, layout] : [layout, insertion]

    #expect(try applying(operations, to: file) ==
      "send(\n  first: 1,\n  middle: 2,\n  last: 3\n)")
  }

  @Test(
    "Boundary insertions follow final order and index insertion keeps its anchor"
  )
  func reorderedAttributes() throws {
    let file = try collect("@Zebra @Apple struct Store {}")
    let declaration = try #require(file.structs.first)
    let list = try declaration.attributeList
    let layout = try Layout(list) {
      Group { _ in true }.sorted { $0.name < $1.name }
    }.correction
    let start = try Insert("@First", into: list, at: .start).correction
    let end = try Insert("@Last", into: list).correction
    let anchored = try Insert("@BeforeZebra", into: list, at: .index(0))
      .correction

    #expect(
      try applying([layout, start, end, anchored], to: file)
        == "@First @Apple @BeforeZebra @Zebra @Last struct Store {}"
    )
  }

  @Test(
    "Width-limited list insertion retains inline edits",
    arguments: [20, 100]
  )
  func insertionWithInlineEdit(maximumWidth: Int) throws {
    let file = try collect("send(first: 1, second: 2)")
    let list = try #require(
      file.syntaxNodes(of: .functionCall)
        .compactMap(\.call).first
    ).argumentList
    let layout = try Layout(list, when: !.maximumLineLength(...maximumWidth)) {
      Newline()
      try Lines {
        try list[0].expressionSource.replacement(with: "42")
        list[1]
      }
      Newline()
    }.correction
    let inserted = try list.inserting("third: 3")

    let expected =
      if maximumWidth == 20 {
        "send(\n  first: 42,\n  second: 2,\n  third: 3\n)"
      } else {
        "send(first: 42, second: 2, third: 3)"
      }
    #expect(try applying([layout, inserted], to: file) == expected)
  }

  @Test("Insertion retains position when its original anchor is removed")
  func removedAnchor() throws {
    let file = try collect("send(first: 1, old: 2, last: 3)")
    let list = try #require(
      file.syntaxNodes(of: .functionCall)
        .compactMap(\.call).first
    ).argumentList
    let inserted = try list.inserting("middle: 4", at: .index(1))
    let removed = try list.removing(list[1])

    #expect(try applying([inserted, removed], to: file) ==
      "send(first: 1, middle: 4, last: 3)")
  }

  @Test("Repeated insertion proposals produce one new element")
  func repeatedInsertion() throws {
    let file = try collect("send()")
    let list = try #require(
      file.syntaxNodes(of: .functionCall)
        .compactMap(\.call).first
    ).argumentList
    let operation = try list.inserting("value: 1")

    #expect(try applying([operation, operation], to: file) == "send(value: 1)")
  }

  @Test("Multiple removals preserve list grammar", arguments: [false, true])
  func removeAll(formatted: Bool) throws {
    let file = try collect("send(first: 1, second: 2)")
    let list = try #require(
      file.syntaxNodes(of: .functionCall)
        .compactMap(\.call).first
    ).argumentList
    var operations = try list.map { try list.removing($0) }
    if formatted {
      operations.append(try Layout(list) { Line { list } }.correction)
    }

    #expect(try applying(operations, to: file) == "send()")
  }

  @Test("Removal rejects a nested edit to the removed argument")
  func conflictingRemoval() throws {
    let file = try collect("send(first: nested(), last: 2)")
    let call = try #require(
      file.syntaxNodes(of: .functionCall)
        .compactMap(\.call).first { $0.calledExpression == "send" }
    )
    let list = try call.argumentList
    let removed = try list.removing(list[0])
    let nested = try #require(
      file.syntaxNodes(of: .functionCall)
        .compactMap(\.call)
        .first { $0.calledExpression == "nested" }
    )
    let replacement =
      SourceCorrection(edits: [
        try nested.nameSource
          .replacement(with: "other"),
      ])

    #expect(throws: SourceError.overlappingEdits) {
      try applying([removed, replacement], to: file)
    }
  }

  @Test("List mutation plans survive encoding")
  func encodedPlans() throws {
    let file = try collect("send(first: 1)")
    let list = try #require(
      file.syntaxNodes(of: .functionCall)
        .compactMap(\.call).first
    ).argumentList
    let fix = try #require(list.inserting("last: 2").fix)
    let data = try JSONEncoder().encode(fix)
    let decoded = try JSONDecoder().decode(SourceFix.self, from: data)

    #expect(
      try file.source.replacement(applying: decoded.edits)
        .replacement == "send(first: 1, last: 2)"
    )
  }

  @Test(
    "Decoded list plan rejects malformed insertion among several operations"
  )
  func malformedEncodedOperation() throws {
    let file = try collect("send(first: 1)")
    let list = try #require(file.syntaxNodes(of: .functionCall).first?.call)
      .argumentList
    let edit = try #require(list.inserting("last: 2").fix?.edits.first)
    var payload = try #require(JSONSerialization.jsonObject(
      with: JSONEncoder().encode(edit)
    ) as? [String: Any])
    var layout = try #require(payload["layout"] as? [String: Any])
    var mode = try #require(layout["mode"] as? [String: Any])
    var encodedMode = try #require(mode["listMutation"] as? [String: Any])
    var plan = try #require(encodedMode["_0"] as? [String: Any])
    var mutations = try #require(plan["mutations"] as? [[String: Any]])
    var mutation = try #require(mutations.first)
    var operations = try #require(mutation["operations"] as? [[String: Any]])
    let original = try #require(operations.first)
    var insertion = try #require(original["insert"] as? [String: Any])
    insertion["_0"] = "broken: )"
    operations.append(["insert": insertion])
    mutation["operations"] = operations
    mutations[0] = mutation
    plan["mutations"] = mutations
    encodedMode["_0"] = plan
    mode["listMutation"] = encodedMode
    layout["mode"] = mode
    payload["layout"] = layout
    let encoded = try JSONSerialization.data(withJSONObject: payload)

    #expect(throws: SourceError.syntaxMismatch) {
      try JSONDecoder().decode(SourceFix.Edit.self, from: encoded)
    }
  }

  @Test("Removal rejects an inline layout edit to the removed argument")
  func conflictingInlineRemoval() throws {
    let file = try collect("send(first: 1, second: 2)")
    let list = try #require(
      file.syntaxNodes(of: .functionCall)
        .compactMap(\.call).first
    ).argumentList
    let layout = try Layout(list) {
      try list[0].expressionSource.replacement(with: "42")
      list[1]
    }.correction
    let removed = try list.removing(list[0])

    #expect(throws: SourceError.overlappingEdits) {
      try applying([layout, removed], to: file)
    }
  }

  private func collect(_ source: String) throws -> SourceFile {
    try FileCollector.collect(source: source, path: "/virtual/Lists.swift")
  }

  private func applying(
    _ operations: [SourceCorrection],
    to file: SourceFile
  ) throws -> String {
    let fix = try #require(SourceCorrection(combining: operations).fix)
    return try file.source.replacement(
      applying: fix.edits,
      layoutCandidates: fix.layoutCandidates
    ).replacement
  }
}
