import BylawsSemantics
import Testing

@Suite("Layout line-length conditions")
struct SourceLayoutConditionTests {
  @Test("Standard ranges keep their bounds", arguments: [
    (SourceLayoutCondition.maximumLineLength(15...15), true),
    (.maximumLineLength(14...14), false),
    (.maximumLineLength(15..<16), true),
    (.maximumLineLength(14..<15), false),
    (.maximumLineLength(15...), true),
    (.maximumLineLength(16...), false),
    (.maximumLineLength(...15), true),
    (.maximumLineLength(...14), false),
    (.maximumLineLength(..<16), true),
    (.maximumLineLength(..<15), false),
    (.maximumLineLength(0..<0), false),
    (.maximumLineLength(-10 ... -1), false),
    (.maximumLineLength(Int.max...), false),
    (.maximumLineLength(...Int.max), true),
    (!.maximumLineLength(...Int.max), false),
    (!.maximumLineLength(...14), true),
    (.maximumLineLength(10...) && .maximumLineLength(...20), true),
    (.maximumLineLength(10...) && .maximumLineLength(...14), false),
    (.maximumLineLength(...14) || .maximumLineLength(16...), false),
    (.maximumLineLength(...14) || .maximumLineLength(15...), true),
  ])
  func rangeBounds(condition: SourceLayoutCondition, applies: Bool) throws {
    let source = "let x = f(1, 2)"
    let file = try collect(source)
    let arguments = try #require(file.calls.first).arguments
    let layout = try Layout(arguments, when: condition) {
      Newline()
      Lines { arguments }
      Newline()
    }
    let fix = try #require(layout.correction.fix)
    let corrected = try file.source.replacement(applying: fix.edits).replacement

    #expect(corrected == (applies ? "let x = f(\n  1,\n  2\n)" : source))
    #expect(layout.correction.outcome == (applies ? .violation : .satisfied))
  }

  @Test("Conditions measure the longest touched line", arguments: [
    SourceLayoutCondition.maximumLineLength(14...16),
    !.maximumLineLength(...10),
  ])
  func longestLine(condition: SourceLayoutCondition) throws {
    let file = try collect("let x = f(1234,\n  2)")
    let arguments = try #require(file.calls.first).arguments
    let edit = try arguments.replacement(when: condition) {
      Newline()
      Lines { arguments }
      Newline()
    }

    #expect(try file.source.replacement(applying: [edit]).replacement == """
    let x = f(
      1234,
      2
    )
    """)
  }

  @Test("Stored and builder layouts include surrounding source")
  func storedValue() throws {
    let file = try collect("let x = f(1, 2).tail")
    let arguments = try #require(file.calls.first).arguments
    let content = SourceLayout {
      Newline()
      Lines { arguments }
      Newline()
    }
    let stored = try arguments.replacement(
      layout: content,
      when: .maximumLineLength(20...20)
    )
    let built = try arguments
      .replacement(when: .maximumLineLength(20...20)) { content }

    #expect(try file.source.replacement(applying: [stored]).replacement == """
    let x = f(
      1,
      2
    ).tail
    """)
    #expect(try file.source.replacement(applying: [built]).replacement == """
    let x = f(
      1,
      2
    ).tail
    """)
  }

  @Test("Negated conditions leave empty lists alone")
  func emptyList() throws {
    let file = try collect("let x = f()")
    let arguments = try #require(file.calls.first).arguments
    let layout = try Layout(arguments, when: !.maximumLineLength(0..<0)) {
      Newline()
      Lines { arguments }
      Newline()
    }

    #expect(layout.correction.outcome == .notApplicable)
    #expect(layout.correction.fix == nil)
  }

  @Test("Nested conditions use final placement", arguments: [false, true])
  func finalPlacement(reversed: Bool) throws {
    let file = try collect("let x = outer(first: inner(1, 2), second: 3)")
    let outer = try #require(file.calls.first { $0.name == "outer" })
    let inner = try #require(file.calls.first { $0.name == "inner" })
    let outerEdit = try outer.arguments.replacement {
      Newline()
      Lines { outer.arguments }
      Newline()
    }
    let innerEdit = try inner.arguments
      .replacement(when: .maximumLineLength(...25)) {
        Newline()
        Lines { inner.arguments }
        Newline()
      }
    let fix = SourceFix(proposedEdits: [innerEdit])
    try #require(fix.edits.isEmpty)
    try #require(fix.layoutCandidates.count == 1)
    let edits = reversed ? [innerEdit, outerEdit] : [outerEdit, innerEdit]

    #expect(try file.source.replacement(applying: edits).replacement == """
    let x = outer(
      first: inner(
        1,
        2
      ),
      second: 3
    )
    """)
  }

  @Test("Spacing checks each affected policy region")
  func policyRegions() throws {
    let file = try collect("func f() {\n  a()\n  b()\n}")
    let statements = try #require(file.syntaxNodes(of: .codeBlock).first)
      .statements
    let layout = try Layout(statements, when: .maximumLineLength(5...5)) {
      BlankLine(before: { _ in true })
    }
    let fix = try #require(layout.correction.fix)

    #expect(try file.source.replacement(applying: fix.edits).replacement == """
    func f() {
      a()

      b()
    }
    """)
  }

  private func collect(_ source: String) throws -> SourceFile {
    try FileCollector.collect(source: source, path: "/virtual/Condition.swift")
  }
}
