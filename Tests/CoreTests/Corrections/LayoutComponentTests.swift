import Bylaws
import BylawsCore
import Testing

@Suite("Stored layout components")
struct LayoutComponentTests {
  @Test("Collection constructor orders attributes on one physical line")
  func attributeLine() async throws {
    let app = Codebase(root: .sources([
      "Sources/Panel.swift": "@Zebra\n@Apple class Panel {}",
    ]))
    let declaration = try #require(await app.classes.first)
    let attributes = declaration.attributes
    let line = Line(attributes.sorted { $0.name < $1.name })
    let operation = try Layout(attributes, layout: line)

    #expect(try applying(operation) == "@Apple @Zebra\nclass Panel {}")
  }

  @Test("Lines value retains multiline arguments and controls outer breaks")
  func argumentLines() async throws {
    let app = Codebase(root: .sources([
      "Sources/Calls.swift": """
      let result = send(first: nested(
        value: 1
      ), second: 2)
      """,
    ]))
    let call = try #require(await app.calls.named("send").first)
    let arguments = try call.argumentList
    let operation = try Layout(
      arguments,
      layout: Lines(arguments, boundaries: .newline)
    )

    #expect(try applying(operation) == """
    let result = send(
      first: nested(
        value: 1
      ),
      second: 2
    )
    """)
  }

  @Test("Component values compose inside builders and stored layouts")
  func componentValues() async throws {
    let app = Codebase(root: .sources([
      "Sources/Calls.swift": "let result = send(first: 1, second: 2)",
    ]))
    let call = try #require(await app.calls.first)
    let component = Align(layout: Wrap(call.arguments, width: 30))
    let stored = try Layout(call.arguments, layout: component)
    let built = try Layout(call.arguments) { component }

    #expect(try applying(stored) == """
    let result = send(first: 1,
                      second: 2)
    """)
    #expect(try applying(built) == applying(stored))
  }

  @Test("Empty Lines value leaves adjacent source on its line")
  func emptyBoundaries() async throws {
    let app = Codebase(root: .sources([
      "Sources/Calls.swift": "let result = send(first: 1, second: 2)",
    ]))
    let call = try #require(await app.calls.first)
    let empty: [FunctionCall.Argument] = []
    let operation = try Layout(call.arguments) {
      call.arguments[0]
      Lines(empty, boundaries: .newline)
      Lines(boundaries: .newline) { Newline() }
      call.arguments[1]
    }

    #expect(operation.correction.outcome == .satisfied)
  }

  @Test(
    "Common literal elements retain complete dictionary entries",
    arguments: [false, true]
  )
  func dictionaryElements(trailingComma: Bool) async throws {
    let comma = trailingComma ? "," : ""
    let app = Codebase(root: .sources([
      "Sources/Calls.swift": "let result = send(values: [key: 1, key: [2, 3]\(comma)])",
    ]))
    let call = try #require(await app.calls.named("send").first)
    let elements = try #require(call.arguments.first?.expression?.elements)
    let operation = try Layout(
      elements,
      layout: Lines(elements, boundaries: .newline)
    )

    #expect(try applying(operation) == """
    let result = send(values: [
      key: 1,
      key: [2, 3]\(comma)
    ])
    """)
    #expect(elements.count == 2)
  }

  @Test(
    "Common literal elements distinguish empty lists from other expressions"
  )
  func emptyElements() async throws {
    let app = Codebase(root: .sources([
      "Sources/Calls.swift": "let result = send([], [:], unknown)",
    ]))
    let call = try #require(await app.calls.first)

    #expect(call.arguments[0].expression?.elements == [])
    #expect(call.arguments[1].expression?.elements == [])
    #expect(call.arguments[2].expression?.elements == nil)
  }

  private func applying(_ operation: some SourceCorrectionProviding) throws
    -> String
  {
    let fix = try #require(operation.correction.fix)
    let source = try #require(fix.edits.first).source.file
    return try source.replacement(applying: fix.edits).replacement
  }
}

extension LayoutComponentTests {
  @Test("Layout takes a named content function")
  func contentFunction() throws {
    func ordering() -> LayoutContent<Property> {
      .group(Group { _ in true }.sorted { $0.name < $1.name })
    }
    let file = try FileCollector.collect(
      source: "struct Item {\n  let zebra = 1\n  let apple = 2\n}",
      path: "/virtual/Item.swift"
    )
    let declaration = try #require(file.structs.first)
    let layout = try Layout(declaration.properties, ordering)
    let fix = try #require(layout.correction.fix)

    #expect(try file.source.replacement(applying: fix.edits).replacement == """
    struct Item {
      let apple = 2
      let zebra = 1
    }
    """)
  }
}
