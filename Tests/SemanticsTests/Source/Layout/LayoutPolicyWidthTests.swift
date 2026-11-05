import BylawsSemantics
import Testing

@Suite("Layout policy width conditions")
struct LayoutPolicyWidthTests {
  @Test("Spacing applies only above the width limit", arguments: [9, 10, 11])
  func spacingThreshold(limit: Int) throws {
    let source = "func work() {\n  first()\n  second()\n}"
    let file = try collect(source)
    let statements = try #require(file.syntaxNodes(of: .codeBlock).first)
      .statements
    let operation = try Layout(
      statements,
      when: !.maximumLineLength(...limit)
    ) {
      BlankLine(before: { _ in true })
    }
    let fix = try #require(operation.correction.fix)
    let corrected = try file.source.replacement(applying: fix.edits).replacement

    #expect(corrected == (limit == 9
        ? "func work() {\n  first()\n\n  second()\n}"
        : source))
    #expect(fix.layoutCandidates.count == (limit == 9 ? 0 : 1))
  }

  @Test("Spacing preserves gaps outside the changed region")
  func unchangedGaps() throws {
    let file = try collect("""
    func work() {
      first()
      second()


      third()
    }
    """)
    let statements = try #require(file.syntaxNodes(of: .codeBlock).first)
      .statements
    let operation = try Layout(statements, when: !.maximumLineLength(...9)) {
      BlankLine(before: { $0.call?.references("second") == true })
    }
    let fix = try #require(operation.correction.fix)

    #expect(try file.source.replacement(applying: fix.edits).replacement == """
    func work() {
      first()

      second()


      third()
    }
    """)
  }

  @Test(
    "Grouped policies apply only above the width limit",
    arguments: [15, 16, 17]
  )
  func groupThreshold(limit: Int) throws {
    let source = "struct Item {\n  let second = 2\n  let first = 1\n}"
    let file = try collect(source)
    let members = try #require(file.syntaxNodes(of: .structDeclaration).first)
      .members
    let operation = try Layout(members, when: !.maximumLineLength(...limit)) {
      Group { _ in true }.sorted { ($0.name ?? "") < ($1.name ?? "") }
      BlankLine(after: { $0.name == "first" })
    }
    let fix = try #require(operation.correction.fix)

    #expect(try file.source.replacement(applying: fix.edits)
      .replacement == (limit == 15
        ? "struct Item {\n  let first = 1\n\n  let second = 2\n}"
        : source))
  }

  @Test("Nested spacing uses the final parent placement")
  func nestedPlacement() throws {
    let file =
      try collect(
        "let value = outer(longPrefix: 1, value: inner(first: 1, second: 2))"
      )
    let outer = try #require(file.calls
      .first { $0.calledExpression == "outer" })
    let inner = try #require(file.calls
      .first { $0.calledExpression == "inner" })
    let outerLayout = try Layout(outer.arguments) {
      Newline()
      Lines { outer.arguments }
      Newline()
    }
    let innerLayout = try Layout(
      inner.arguments,
      when: !.maximumLineLength(...60)
    ) {
      Newline(before: { _ in true })
    }
    let outerFix = try #require(outerLayout.correction.fix)
    let innerFix = try #require(innerLayout.correction.fix)

    #expect(innerFix.edits.count == 1)
    #expect(try file.source.replacement(
      applying: outerFix.edits + innerFix.edits
    ).replacement == """
    let value = outer(
      longPrefix: 1,
      value: inner(first: 1, second: 2)
    )
    """)
  }

  private func collect(_ source: String) throws -> SourceFile {
    try FileCollector.collect(source: source, path: "/virtual/Width.swift")
  }
}
