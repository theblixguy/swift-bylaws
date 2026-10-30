import Testing
@testable import BylawsSemantics

@Suite("Source layout event lowering")
struct SourceLayoutLoweringTests {
  @Test(
    "Sequences retain only separators between emitted children",
    arguments: [
      (
        SourceLayout.Node.sequence([]), SourceLayoutRenderer.Separator.space,
        [String](), ""
      ),
      (
        .sequence([
          .sequence([]), .source(Text("a")), .sequence([]),
          .source(Text("b")), .sequence([]),
        ]), .space, ["text:a", "soft", "text:b"], "a b"
      ),
      (
        .sequence([
          .source(Text("a")), .sequence([
            .source(Text("b")), .source(Text("c")),
          ]), .source(Text("d")),
        ]), .newline,
        [
          "text:a",
          "newline",
          "text:b",
          "newline",
          "text:c",
          "newline",
          "text:d",
        ],
        "a\nb\nc\nd"
      ),
      (
        .sequence([
          .source(Text("a")), .source(Text("")), .source(Text("b")),
        ]), .space,
        ["text:a", "soft", "text:", "soft", "text:b"], "a b"
      ),
      (
        .sequence([
          .source(Text("a")), .sequence([.blankLine]), .source(Text("b")),
        ]), .newline,
        ["text:a", "newline", "blankLine", "newline", "text:b"], "a\n\nb"
      ),
      (
        .sequence([
          .source(Text("a")), .line(.source(Text(""))), .source(Text("b")),
        ]), .newline, ["text:a", "newline", "text:b"], "a\nb"
      ),
      (
        .sequence([
          .source(Text("a")), .line(.sequence([.newline, .blankLine])),
          .source(Text("b")),
        ]), .space, ["text:a", "soft", "text:b"], "a b"
      ),
      (
        .sequence([
          .source(Text("a")), .indent(.sequence([])), .align(.sequence([])),
          .wrap(width: nil, .sequence([])), .source(Text("b")),
        ]), .space, ["text:a", "soft", "text:b"], "a b"
      ),
      (
        .sequence([
          .source(Text("a")), .indent(.newline), .source(Text("b")),
        ]), .space,
        ["text:a", "soft", "lineBoundary", "soft", "text:b"], "a\nb"
      ),
      (
        .sequence([
          .source(Text("a")), .align(.blankLine), .source(Text("b")),
        ]), .newline,
        ["text:a", "newline", "blankLine", "newline", "text:b"], "a\n\nb"
      ),
      (
        .sequence([
          .source(Text("a")), .wrap(width: 1, .softBreak), .source(Text("b")),
        ]), .space,
        ["text:a", "soft", "soft", "soft", "text:b"], "a b"
      ),
    ]
  )
  func sequences(
    node: SourceLayout.Node, separator: SourceLayoutRenderer.Separator,
    expectedEvents: [String], expectedText: String
  ) throws {
    let document = try document(node, separator: separator)

    #expect(shape(document.events) == expectedEvents)
    #expect(try SourceLayoutRenderer
      .render(document, context: .init()) == expectedText)
  }

  @Test(
    "Empty style scopes retain boundaries without style tags",
    arguments: [
      (
        SourceLayout.Node.indent(.sequence([])),
        [String](), "ab"
      ),
      (.align(.sequence([])), [], "ab"),
      (.wrap(width: 1, .sequence([])), [], "ab"),
      (
        .indent(.align(.wrap(width: nil, .source(Text(""))))),
        ["text:"], "ab"
      ),
      (.indent(.newline), ["lineBoundary"], "a\nb"),
      (.align(.blankLine), ["blankLine"], "a\n\nb"),
      (.wrap(width: 1, .softBreak), ["soft"], "a b"),
      (
        .indent(.align(.wrap(width: nil, .sequence([.newline, .blankLine])))),
        ["lineBoundary", "soft", "blankLine"], "a\n\nb"
      ),
      (
        .wrap(width: nil, .sequence([.newline, .softBreak])),
        ["lineBoundary", "soft", "soft"], "a\nb"
      ),
    ]
  )
  func emptyScopes(
    node: SourceLayout.Node, expectedEvents: [String], expectedText: String
  ) throws {
    let lowered = try document(node, separator: .newline)
    let document = SourceLayoutDocument(events:
      [.text("a")] + lowered.events + [.text("b")]
    )

    #expect(shape(lowered.events) == expectedEvents)
    #expect(try SourceLayoutRenderer
      .render(document, context: .init()) == expectedText)
  }

  @Test(
    "Lines discard textless children and use spaces for retained children",
    arguments: [
      (SourceLayout.Node.sequence([]), [String](), ""),
      (.sequence([.newline, .blankLine, .softBreak]), [], ""),
      (.source(Text("")), [], ""),
      (
        .sequence([.source(Text("a")), .sequence([]), .source(Text("b"))]),
        ["line[text:a, soft, text:b]"], "a b"
      ),
    ]
  )
  func lines(
    child: SourceLayout.Node, expectedEvents: [String], expectedText: String
  ) throws {
    let document = try document(.line(child), separator: .newline)

    #expect(shape(document.events) == expectedEvents)
    #expect(try SourceLayoutRenderer
      .render(document, context: .init()) == expectedText)
  }

  @Test(
    "Text scopes retain their opening and closing styles",
    arguments: [
      (
        SourceLayout.Node.indent(.source(Text("a"))),
        ["indent", "text:a", "endIndentation"]
      ),
      (.align(.source(Text("a"))), ["align", "text:a", "endIndentation"]),
      (.wrap(width: 3, .source(Text("a"))), ["wrap:3", "text:a", "endWrap"]),
      (
        .wrap(width: nil, .source(Text("a"))),
        ["wrap:default", "text:a", "endWrap"]
      ),
    ]
  )
  func textScopes(node: SourceLayout.Node, expectedEvents: [String]) throws {
    let document = try document(node, separator: .space)

    #expect(shape(document.events) == expectedEvents)
  }

  @Test(
    "Textless inner styles preserve their active outer scope",
    arguments: [
      SourceLayout.Node.align(.newline), .indent(.newline),
      .wrap(width: nil, .newline),
    ]
  )
  func nestedScopes(inner: SourceLayout.Node) throws {
    let document = try document(.indent(.sequence([
      .source(Text("a")), inner, .source(Text("b")),
    ])), separator: .space)

    #expect(shape(document.events) == [
      "indent", "text:a", "soft", "lineBoundary", "soft", "text:b",
      "endIndentation",
    ])
    #expect(try SourceLayoutRenderer
      .render(document, context: .init()) == "a\n  b")
  }

  @Test(
    "Edits retain their event and sequence separators",
    arguments: [
      ("", ["text:a", "soft", "text:", "soft", "text:b"], "a b"),
      (
        "edited",
        ["text:a", "soft", "text:edited", "soft", "text:b"],
        "a edited b"
      ),
    ]
  )
  func edits(
    replacement: String,
    expectedEvents: [String],
    expectedText: String
  ) throws {
    let edit = try Text("original").source.replacement(with: replacement)
    let document = try document(.sequence([
      .source(Text("a")), .edit(edit), .source(Text("b")),
    ]), separator: .space)

    #expect(shape(document.events) == expectedEvents)
    #expect(try SourceLayoutRenderer
      .render(document, context: .init()) == expectedText)
  }

  @Test(
    "Invalid wrapping width throws for textless children",
    arguments: [0, -1], [
      SourceLayout.Node.sequence([]), .newline, .line(.blankLine),
    ]
  )
  func invalidWidth(width: Int, child: SourceLayout.Node) {
    #expect(throws: SourceLayoutError.widthMustBePositive) {
      try document(.wrap(width: width, child), separator: .space)
    }
  }

  private func document(
    _ node: SourceLayout.Node, separator: SourceLayoutRenderer.Separator
  ) throws -> SourceLayoutDocument {
    try SourceLayoutDocument(
      node, separator: separator,
      source: { .text(try $0.source.text) },
      edit: { .text($0.replacement) }
    )
  }

  private func shape(_ events: [SourceLayoutDocument.Event]) -> [String] {
    events.map { event in
      switch event {
      case let .text(text): "text:\(text)"
      case let .line(events): "line[\(shape(events).joined(separator: ", "))]"
      case .boundary(.soft): "soft"
      case .boundary(.newline): "newline"
      case .boundary(.blankLine): "blankLine"
      case .lineBoundary: "lineBoundary"
      case .indent: "indent"
      case .align: "align"
      case .endIndentation: "endIndentation"
      case let .wrap(width): "wrap:\(width.map { String($0) } ?? "default")"
      case .endWrap: "endWrap"
      case .content: "content"
      case .element: "element"
      case .layout: "layout"
      }
    }
  }

  private struct Text: SourceProviding {
    let value: String

    init(_ value: String) { self.value = value }

    var source: SourceSlice {
      get throws {
        try SourceSlice(
          snapshot: SourceSnapshot(
            filePath: "/Text.swift", text: value, swiftLanguageMode: .v6
          ), range: 0..<value.utf8.count
        )
      }
    }
  }
}
