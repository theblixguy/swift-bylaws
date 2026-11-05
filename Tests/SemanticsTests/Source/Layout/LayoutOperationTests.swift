import BylawsSemantics
import Testing

@Suite("Layout correction operations")
struct LayoutOperationTests {
  @Test(
    "Stored components and builder components produce requested attribute order"
  )
  func storedComponents() throws {
    let file = try collect("@Zebra @Apple struct Item {}")
    let attributes = try #require(file.structs.first).attributes
    let operation = try Layout(attributes, layout: .sequence([
      .group(Group { _ in true }.sorted { $0.name < $1.name }),
    ]))

    #expect(try applying(operation, to: file) == "@Apple @Zebra struct Item {}")
    #expect(operation.correction.outcome == .violation)
  }

  @Test("Stored layout values compose without a result builder")
  func storedLayout() throws {
    let file = try collect("let value = send(first: 1, second: 2)")
    let arguments = try #require(file.calls.first).arguments
    let rows = Lines(layout: SourceLayout(arguments)).layout
    let layout = SourceLayout([.newline, rows, .newline])
    let operation = try Layout(arguments, layout: layout)

    #expect(try applying(operation, to: file) == """
    let value = send(
      first: 1,
      second: 2
    )
    """)
  }

  @Test("Lines retain multiline argument content")
  func multilineElements() throws {
    let file = try collect("""
    let value = send(first: nested(
      value: 1
    ), second: 2)
    """)
    let arguments = try #require(file.calls
      .first { $0.calledExpression == "send" })
      .arguments
    let operation = try Layout(arguments) {
      Newline()
      Lines { arguments }
      Newline()
    }

    #expect(try applying(operation, to: file) == """
    let value = send(
      first: nested(
        value: 1
      ),
      second: 2
    )
    """)
  }

  @Test("Lines leave list boundaries unchanged")
  func boundaries() throws {
    let file = try collect("let value = send(first: 1, second: 2)")
    let arguments = try #require(file.calls.first).arguments
    let operation = try Layout(arguments) {
      Lines { arguments }
    }

    #expect(try applying(operation, to: file) ==
      "let value = send(first: 1,\n  second: 2)")
  }

  @Test("Empty collections need no correction")
  func emptyCollection() throws {
    let arguments: [FunctionCall.Argument] = []
    let operation = try Layout(arguments) {
      Newline()
      Lines { arguments }
      Newline()
    }

    let layouts = [
      operation,
      try Layout(arguments) { Line { arguments } },
      try Layout(arguments) { Align { Wrap(width: 80) { arguments } } },
    ]
    for layout in layouts {
      #expect(layout.correction.outcome == .notApplicable)
      #expect(layout.correction.fix == nil)
    }
  }

  @Test("Inactive layout branches leave nonempty lists unchanged")
  func inactiveLayout() throws {
    let file = try collect("let result = send(first: 1, second: 2)")
    let arguments = try #require(file.calls.first).arguments
    let operation = try Layout(arguments) {
      if false { Group { _ in true } }
    }
    let stored = try Layout(
      arguments,
      layout: Lines { SourceLayout([]) }.layout
    )

    #expect(operation.correction.outcome == .notApplicable)
    #expect(operation.correction.fix == nil)
    #expect(stored.correction.outcome == .notApplicable)
    #expect(stored.correction.fix == nil)
    #expect(throws: SourceLayoutReplacementError.missingElement) {
      try Layout(arguments) { Newline() }
    }
  }

  @Test("Explicit source and automatic groups cannot share one layout")
  func mixedContent() throws {
    let file = try collect("@First @Second struct Item {}")
    let attributes = try #require(file.structs.first).attributes

    #expect(throws: SourceListLayoutError.mixedContent) {
      try Layout(attributes) {
        attributes
        Group { _ in true }
      }
    }
  }

  @Test("Empty input still checks layout parameters")
  func emptyParameters() throws {
    let arguments: [FunctionCall.Argument] = []

    #expect(throws: SourceListLayoutError.unsupportedSeparator) {
      try Layout(arguments, layout: .separator(.space))
    }
  }

  @Test(
    "Stored layouts preserve unavailable correction errors",
    arguments: [false, true]
  )
  func preparationErrors(knownViolation: Bool) throws {
    let file = try collect("let value = send(first: 1, second: 2)")
    let arguments = try #require(file.calls.first).arguments
    let correction: SourceCorrection = knownViolation
      ? .unavailable("The comment has no clear owner.")
      : .undetermined("The enclosing context is unknown.")
    let expected: SourceCorrectionError = knownViolation
      ? .unavailable("The comment has no clear owner.")
      : .undetermined("The enclosing context is unknown.")
    let layout = SourceLayout {
      correction
    }

    let operation = try Layout(arguments, layout: layout)
    #expect(operation.correction.outcome == correction.outcome)
    #expect(operation.correction.reason == correction.reason)
    #expect(operation.correction.fix == nil)
    #expect(throws: expected) {
      try arguments.replacement { correction }
    }
  }

  @Test("Nested operations compose with existing source replacements")
  func nestedOperation() throws {
    let file = try collect("let value = send(first: [1, 2], second: 2)")
    let arguments = try #require(file.calls.first).arguments
    let elements = try #require(arguments.first?.expression?.arrayElements)
    let nested = try Layout(elements) {
      Newline()
      Lines { elements }
      Newline()
    }
    let replacement = try arguments.replacement {
      Newline()
      nested
      Newline()
      try arguments[1].expressionSource.replacement(with: "3")
      Newline()
    }

    #expect(try file.source.replacement(applying: [replacement])
      .replacement == """
      let value = send(
        first: [
          1,
          2
        ],
        second: 3
      )
      """)
  }

  private func collect(_ source: String) throws -> SourceFile {
    try FileCollector.collect(source: source, path: "/virtual/Layout.swift")
  }

  private func applying(
    _ operation: Layout<some SourceProviding>, to file: SourceFile
  ) throws -> String {
    let fix = try #require(operation.correction.fix)
    return try file.source.replacement(applying: fix.edits).replacement
  }
}
