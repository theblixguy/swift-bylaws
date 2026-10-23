import BylawsSemantics
import Testing

@Suite("Source list spacing")
struct SourceListSpacingTests {
  @Test("Empty spacing selections produce no edits")
  func emptySelection() throws {
    let statements: [SourceNode] = []
    let fix: SourceFix = try statements.replacement {
      BlankLine(before: { _ in true })
    }

    #expect(fix.edits.isEmpty)
  }

  @Test(
    "Between separators match both adjacent orders",
    arguments: [false, true]
  )
  func symmetricSpacing(reversed: Bool) throws {
    let first = reversed ? "await send()" : "let value = 0"
    let second = reversed ? "let value = 0" : "await send()"
    let file = try collect("func work() async {\n  \(first)\n  \(second)\n}")
    let statements = try #require(file.syntaxNodes(of: .codeBlock).first)
      .statements
    let fix: SourceFix = try statements.replacement {
      BlankLine(
        between: { $0.kind == .variableDeclaration },
        and: { $0.call != nil }
      )
    }

    #expect(try applying(fix, to: file) ==
      "func work() async {\n  \(first)\n\n  \(second)\n}")
  }

  @Test(
    "Before and after separators retain directional meaning",
    arguments: [false, true]
  )
  func directionalSpacing(before: Bool) throws {
    let file = try collect("func work() {\n  first()\n  middle()\n  last()\n}")
    let statements = try #require(file.syntaxNodes(of: .codeBlock).first)
      .statements
    let fix: SourceFix = try statements.replacement {
      if before {
        BlankLine(before: { $0.call?.references("middle") == true })
      } else {
        BlankLine(after: { $0.call?.references("middle") == true })
      }
    }

    #expect(try applying(fix, to: file) == (before
        ? "func work() {\n  first()\n\n  middle()\n  last()\n}"
        : "func work() {\n  first()\n  middle()\n\n  last()\n}"))
  }

  @Test("Newline removes blank lines at matching gaps")
  func singleNewline() throws {
    let file = try collect("func work() {\n  first()\n\n\n  second()\n}")
    let statements = try #require(file.syntaxNodes(of: .codeBlock).first)
      .statements
    let fix: SourceFix = try statements.replacement {
      Newline(between: { $0.call != nil }, and: { $0.call != nil })
    }

    #expect(try applying(fix, to: file) ==
      "func work() {\n  first()\n  second()\n}")
  }

  @Test(
    "Unmatched gaps retain exact whitespace, tabs and Unicode",
    arguments: ["\n", "\r\n", "\r"]
  )
  func unchangedGaps(ending: String) throws {
    let source = "func work() async {\(ending)\tlet café = 0\(ending)\(ending)\(ending)\tlet other = 1\(ending)\tawait send()\(ending)\tawait record()\(ending)}"
    let file = try collect(source)
    let statements = try #require(file.syntaxNodes(of: .codeBlock).first)
      .statements
    let fix: SourceFix = try statements.replacement {
      BlankLine(before: { $0.call?.references("send") == true })
    }
    let corrected = try applying(fix, to: file)

    #expect(corrected ==
      "func work() async {\(ending)\tlet café = 0\(ending)\(ending)\(ending)\tlet other = 1\(ending)\(ending)\tawait send()\(ending)\tawait record()\(ending)}")
    let parsed = try collect(corrected)
    let correctedStatements = try #require(parsed.syntaxNodes(of: .codeBlock)
      .first).statements
    let second: SourceFix = try correctedStatements.replacement {
      BlankLine(before: { $0.call?.references("send") == true })
    }
    #expect(second.edits.isEmpty)
  }

  @Test("Repeated separator requests combine without duplicate edits")
  func repeatedSeparators() throws {
    let file = try collect("func work() {\n  first()\n  second()\n}")
    let statements = try #require(file.syntaxNodes(of: .codeBlock).first)
      .statements
    let fix: SourceFix = try statements.replacement {
      BlankLine(before: { $0.call?.references("second") == true })
      BlankLine(after: { $0.call?.references("first") == true })
    }

    #expect(fix.edits.count == 1)
    #expect(try applying(fix, to: file) ==
      "func work() {\n  first()\n\n  second()\n}")
  }

  @Test("Conflicting separator requests reject correction")
  func conflictingSeparators() throws {
    let file = try collect("func work() {\n  first()\n  second()\n}")
    let statements = try #require(file.syntaxNodes(of: .codeBlock).first)
      .statements

    #expect(throws: SourceListLayoutError.conflictingSeparators) {
      let _: SourceFix = try statements.replacement {
        BlankLine(after: { _ in true })
        Newline(before: { _ in true })
      }
    }
  }

  private func collect(_ source: String) throws -> SourceFile {
    try FileCollector.collect(
      source: source,
      path: "/virtual/SourceLists.swift"
    )
  }

  private func applying(
    _ fix: SourceFix,
    to file: SourceFile
  ) throws -> String {
    try file.source.replacement(applying: fix.edits).replacement
  }
}
