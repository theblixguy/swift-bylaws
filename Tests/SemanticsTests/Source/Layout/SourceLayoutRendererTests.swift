import BylawsSemantics
import Testing

@Suite("Source layout rendering")
struct SourceLayoutRendererTests {
  @Test("Line emits attributes in selected order")
  func attributeLine() throws {
    let observable = try source("@Observable")
    let actor = try source("@MainActor")
    let layout = SourceLayoutBuilder.buildBlock(
      SourceLayoutBuilder.buildExpression(Line {
        observable
        actor
      })
    )

    #expect(try render(layout) == "@Observable @MainActor")
  }

  @Test("Builder keeps conditions and loops in source order")
  func controlFlow() throws {
    let sources = try ["alpha", "beta", "gamma"].map(source)
    let includeFirst = true
    let layout = makeLayout {
      if includeFirst {
        sources[0]
      }
      for source in sources.dropFirst() {
        Line { source }
      }
    }

    #expect(try render(layout) == "alpha\nbeta\ngamma")
  }

  @Test("Empty groups collapse blank-line requests")
  func emptySections() throws {
    let first = try source("first")
    let last = try source("last")
    let empty: [SourceSlice] = []
    let layout = makeLayout {
      BlankLine()
      empty
      Line { first }
      BlankLine()
      Indent { empty }
      BlankLine()
      Line { last }
      BlankLine()
    }

    #expect(try render(layout) == "first\n\nlast")
  }

  @Test("Wrapping counts Unicode characters at exact width", arguments: [
    (7, "café 🦊"),
    (6, "café\n🦊"),
  ])
  func unicodeWidth(width: Int, expected: String) throws {
    let first = try source("café")
    let second = try source("🦊")
    let layout = makeLayout {
      Wrap(width: width) {
        first
        second
      }
    }

    #expect(try render(layout, context: .init(initialColumn: 1)) == expected)
  }

  @Test("Wrapping uses configured width")
  func defaultWidth() throws {
    let values = try ["one", "two", "three"].map(source)
    let layout = makeLayout {
      Wrap { values }
    }

    #expect(try render(layout, context: .init(defaultWidth: 7)) ==
      "one two\nthree")
  }

  @Test("Indent applies to wrapped continuation lines")
  func continuationIndent() throws {
    let values = try ["first", "second", "third"].map(source)
    let layout = makeLayout {
      Indent {
        Wrap(width: 13) { values }
      }
    }

    #expect(
      try render(
        layout,
        context: .init(initialColumn: 4, baseIndentation: "  ")
      )
        == "first\n    second\n    third"
    )
  }

  @Test("Align follows starting column after separator")
  func continuationAlignment() throws {
    let first = try source("call(")
    let values = try ["first", "second", "third"].map(source)
    let layout = makeLayout {
      first
      Align {
        Wrap(width: 15) { values }
      }
    }

    #expect(try render(layout) == "call( first\n      second\n      third")
  }

  @Test("Wrapping counts tabs at tab stops")
  func tabWidth() throws {
    let first = try source("a\tb")
    let second = try source("cc")
    let layout = makeLayout {
      Wrap(width: 7) {
        first
        second
      }
    }

    #expect(try render(layout, context: .init(tabWidth: 4)) == "a\tb\ncc")
  }

  @Test("Blank lines use configured line endings")
  func lineEndings() throws {
    let first = try source("first")
    let last = try source("last")
    let layout = makeLayout {
      first
      BlankLine()
      last
    }

    #expect(try render(layout, context: .init(lineEnding: "\r\n")) ==
      "first\r\n\r\nlast")
  }

  @Test("Multiline source rebases outer indentation")
  func multilineSource() throws {
    let value = "    func load() {\r\n      read()\r\n    }"
    let snapshot = SourceSnapshot(
      filePath: "/mock.swift",
      text: value,
      swiftLanguageMode: .v6
    )
    let body = try SourceSlice(snapshot: snapshot, range: 4..<value.utf8.count)
    let layout = makeLayout { body }

    #expect(
      try render(
        layout,
        context: .init(baseIndentation: "  ", lineEnding: "\r\n")
      )
        == "func load() {\r\n    read()\r\n  }"
    )
  }

  @Test("Line rejects multiline source")
  func multilineLine() throws {
    let value = try source("@First\n@Second")
    let layout = makeLayout { Line { value } }

    #expect(throws: SourceLayoutError.lineContainsNewline) {
      try render(layout)
    }
  }

  @Test("Line rejects nested hard breaks")
  func hardBreakInLine() throws {
    let value = try source("value")
    let layout = makeLayout {
      Line {
        value
        BlankLine()
        value
      }
    }

    #expect(throws: SourceLayoutError.lineContainsNewline) {
      try render(layout)
    }
  }

  @Test("Wrapping width must be positive", arguments: [0, -1])
  func nonpositiveWidth(width: Int) throws {
    let value = try source("value")
    let layout = makeLayout { Wrap(width: width) { value } }

    #expect(throws: SourceLayoutError.widthMustBePositive) {
      try render(layout)
    }
  }

  @Test("Unicode line separators retain literal contents")
  func unicodeLineSeparator() throws {
    let value = try source("\"first\u{2028}second\"")
    let layout = makeLayout { Line { value } }

    #expect(try render(layout) == "\"first\u{2028}second\"")
  }

  @Test("Terminal lines survive empty trailing sections")
  func terminalLine() throws {
    let value = try source("value")
    let empty: [SourceSlice] = []
    let layout = makeLayout {
      Line { value }
      BlankLine()
      Indent { empty }
    }

    let context = SourceLayoutRenderer.Context(
      leadingWhitespace: " ", trailingWhitespace: " ",
      hasSourceBefore: true, hasSourceAfter: true
    )
    #expect(try render(layout, context: context) == "\nvalue\n")
    #expect(try render(makeLayout { value }, context: context) == " value ")
    #expect(try render(makeLayout { Line { empty } }, context: context) == "")
  }

  @Test("Layout operations propagate builder errors")
  func throwingBuilder() {
    #expect(throws: SourceError.unavailable) {
      try Line {
        try failingLayout()
      }
    }
  }

  @Test("Layouts retain reusable source arrangements")
  func reusableLayout() throws {
    let values = try ["@Observable", "@MainActor"].map(source)
    let attributes = SourceLayout { Line { values } }
    let layout = SourceLayout {
      attributes
    }

    #expect(try render(layout) == "@Observable @MainActor")
  }

  @Test("Hard lines flatten optional wrapping layouts")
  func hardLineWithWrap() throws {
    let values = try ["@Observable", "@MainActor"].map(source)
    let wrapping = SourceLayout { Wrap(width: 1) { values } }
    let layout = SourceLayout { Line { wrapping } }

    #expect(try render(layout) == "@Observable @MainActor")
  }

  @Test("Hard lines collapse leading and trailing break requests")
  func hardLineEdges() throws {
    let value = try source("value")
    let layout = SourceLayout {
      Line {
        BlankLine()
        Line { value }
        BlankLine()
      }
    }

    #expect(try render(layout) == "value")
  }

  @Test("Hard lines reject interior line boundaries")
  func interiorLines() throws {
    let first = try source("first")
    let second = try source("second")
    let layout = SourceLayout {
      Line {
        Line { first }
        Line { second }
      }
    }

    #expect(throws: SourceLayoutError.lineContainsNewline) {
      try render(layout)
    }
  }

  @Test("Required breaks survive wrappers without source")
  func requiredBreak() throws {
    let first = try source("first")
    let last = try source("last")
    let layout = SourceLayout {
      first
      Indent { Newline() }
      last
    }

    #expect(try render(layout) == "first\nlast")
  }

  @Test("Required edge breaks identify list boundaries")
  func requiredEdges() throws {
    let value = try source("value")
    let empty: [SourceSlice] = []
    let layout = SourceLayout {
      empty
      Align { Newline() }
      value
      Wrap { Newline() }
      empty
    }

    let context = SourceLayoutRenderer.Context(
      leadingWhitespace: " ", trailingWhitespace: " ",
      hasSourceBefore: true, hasSourceAfter: true
    )
    #expect(try render(layout, context: context) == "\nvalue\n")
    #expect(try render(layout) == "value")
    #expect(try render(SourceLayout { Line { Newline() } }, context: context) ==
      "")
  }

  @Test("Boundary lines use active indentation on first output")
  func boundaryIndentation() throws {
    let values = try ["first", "last"].map(source)
    let layout = SourceLayout {
      Indent {
        for value in values {
          Line { value }
        }
      }
    }
    let context = SourceLayoutRenderer.Context(
      baseIndentation: "  ",
      leadingWhitespace: "\n  ",
      trailingWhitespace: "\n",
      hasSourceBefore: true,
      hasSourceAfter: true,
      closingIndentation: ""
    )

    #expect(try render(layout, context: context) == "\n    first\n    last\n")
  }

  @Test("Layouts preserve unrequested boundary whitespace")
  func preservedBoundaryWhitespace() throws {
    let values = try ["first", "last"].map(source)
    let layout = SourceLayout { values }
    let context = SourceLayoutRenderer.Context(
      initialColumn: 8,
      leadingWhitespace: " \t",
      trailingWhitespace: "  ",
      hasSourceBefore: true,
      hasSourceAfter: true
    )

    #expect(try render(layout, context: context) == " \tfirst last  ")
  }

  @Test("Alignment follows requested boundary newline")
  func boundaryAlignment() throws {
    let values = try ["one", "two"].map(source)
    let layout = SourceLayout {
      Newline()
      Align { Wrap(width: 7) { values } }
    }
    let context = SourceLayoutRenderer.Context(
      initialColumn: 10,
      baseIndentation: "  ",
      hasSourceBefore: true
    )

    #expect(try render(layout, context: context) == "\n  one\n  two")
  }

  @Test("Source access occurs when rendering")
  func lazySource() {
    let layout = makeLayout { MissingSource() }

    #expect(throws: SourceError.unavailable) {
      try render(layout)
    }
  }

  @Test("Edit leaves retain original source identity")
  func editSource() throws {
    let value = try source("old")
    let layout = makeLayout { value.replacement(with: "new") }

    #expect(try layout.sources.map { try $0.source } == [value])
    #expect(layout.edits.map(\.replacement) == ["new"])
    #expect(try render(layout) == "new")
  }

  @Test("Newline separators keep declarations on separate lines")
  func declarationSeparator() throws {
    let values = try ["let first = 1", "let second = 2"].map(source)
    let layout = makeLayout { values }

    #expect(
      try render(
        layout,
        context: .init(baseIndentation: "  ", defaultSeparator: .newline)
      )
        == "let first = 1\n  let second = 2"
    )
  }

  @Test("Explicit breaks use surrounding wrap width")
  func explicitBreak() throws {
    let first = try source("first")
    let second = try source("second")
    let layout = makeLayout {
      Wrap(width: 8) {
        first
        Break()
        second
      }
    }

    #expect(try render(layout) == "first\nsecond")
  }

  private func source(_ text: String) throws -> SourceSlice {
    try SourceSlice(
      snapshot: SourceSnapshot(
        filePath: "/mock.swift",
        text: text,
        swiftLanguageMode: .v6
      ),
      range: 0..<text.utf8.count
    )
  }

  private func makeLayout(@SourceLayoutBuilder _ content: () -> SourceLayout)
    -> SourceLayout
  {
    content()
  }

  private func render(
    _ layout: SourceLayout,
    context: SourceLayoutRenderer.Context = .init()
  ) throws -> String {
    try SourceLayoutRenderer
      .render(layout, context: context) { provider, placement in
        let source = try provider.source
        let prefix = String(
          decoding: source.snapshot.text.utf8.prefix(source.range.lowerBound),
          as: UTF8.self
        )
        return try SourceLayoutText(
          source.text,
          originalIndentation: SourceLayoutText
            .indentation(in: SourceLayoutText.lastLine(in: prefix)),
          indentation: placement.indentation
        ).text
      }
  }

  private func failingLayout() throws -> SourceLayout {
    throw SourceError.unavailable
  }

  private struct MissingSource: SourceProviding {
    var source: SourceSlice { get throws { throw SourceError.unavailable } }
  }
}
