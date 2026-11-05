import BylawsSemantics
import Testing

@Suite("Source list safety")
struct SourceListSafetyTests {
  @Test("Attached documentation moves with grouped declaration")
  func attachedDocumentation() throws {
    let file = try collect("""
    struct Store {
      /// Last property.
      let zebra = 1
      /// First property.
      let apple = 2
    }
    """)
    let members = try #require(file.syntaxNodes(of: .structDeclaration).first)
      .members
    let fixLayout = try Layout(members) {
      Group { _ in true }.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
    let fix: SourceFix = try #require(fixLayout.correction.fix)

    #expect(try applying(fix, to: file) == """
    struct Store {
      /// First property.
      let apple = 2
      /// Last property.
      let zebra = 1
    }
    """)
  }

  @Test(
    "Unclear comments and formatting controls stop grouped correction",
    arguments: [
      "  let zebra = 1 // Keep here.\n  let apple = 2",
      "  // swiftformat:disable\n  let zebra = 1\n  let apple = 2",
      "  // swiftlint:disable all\n  let zebra = 1\n  let apple = 2",
    ]
  )
  func ambiguousComments(_ body: String) throws {
    let file = try collect("struct Store {\n\(body)\n}")
    let members = try #require(file.syntaxNodes(of: .structDeclaration).first)
      .members

    #expect(throws: SourceLayoutReplacementError.ambiguousTrivia) {
      let layout = try Layout(members) {
        Group { _ in true }.sorted { ($0.name ?? "") < ($1.name ?? "") }
      }
      let _: SourceFix = try #require(layout.correction.fix)
    }
  }

  @Test("Modified comment-bearing gaps reject spacing correction")
  func modifiedComments() throws {
    let file =
      try collect("func work() {\n  first() // Keep here.\n  second()\n}")
    let statements = try #require(file.syntaxNodes(of: .codeBlock).first)
      .statements

    #expect(throws: SourceLayoutReplacementError.ambiguousTrivia) {
      let layout = try Layout(statements) {
        BlankLine(before: { $0.call?.references("second") == true })
      }
      let _: SourceFix = try #require(layout.correction.fix)
    }
  }

  @Test("Unmatched comment-bearing gaps remain unchanged")
  func unmatchedComments() throws {
    let file =
      try collect(
        "func work() {\n  first() // Keep here.\n  second()\n  third()\n}"
      )
    let statements = try #require(file.syntaxNodes(of: .codeBlock).first)
      .statements
    let fixLayout = try Layout(statements) {
      BlankLine(before: { $0.call?.references("third") == true })
    }
    let fix: SourceFix = try #require(fixLayout.correction.fix)

    #expect(try applying(fix, to: file) ==
      "func work() {\n  first() // Keep here.\n  second()\n\n  third()\n}")
  }

  @Test("Conditional compilation stops source-list correction")
  func conditionalCompilation() throws {
    let file = try collect("""
    struct Store {
      let zebra = 1
      #if DEBUG
      let conditional = 0
      #endif
      let apple = 2
    }
    """)
    let members = try #require(file.syntaxNodes(of: .structDeclaration).first)
      .members

    #expect(throws: SourceLayoutReplacementError.conditionalCompilation) {
      let layout = try Layout(members) {
        Group { _ in true }.sorted { ($0.name ?? "") < ($1.name ?? "") }
      }
      let _: SourceFix = try #require(layout.correction.fix)
    }
  }

  @Test("Different snapshots reject source-list correction")
  func differentSnapshots() throws {
    let first = try collect("struct Store {\n  let first = 1\n}")
    let second = try collect("struct Store {\n  let second = 2\n}")
    let firstMember = try #require(first.syntaxNodes(of: .structDeclaration)
      .first?.members.first)
    let secondMember = try #require(second.syntaxNodes(of: .structDeclaration)
      .first?.members.first)

    #expect(throws: SourceLayoutReplacementError.differentSnapshots) {
      let layout = try Layout([firstMember, secondMember]) {
        Group { _ in true }
      }
      let _: SourceFix = try #require(layout.correction.fix)
    }
  }

  @Test(
    "Missing list elements reject correction even with unmatched predicates"
  )
  func noncontiguousInputs() throws {
    let file =
      try collect(
        "struct Store {\n  let first = 1\n  let middle = 2\n  let last = 3\n}"
      )
    let members = try #require(file.syntaxNodes(of: .structDeclaration).first)
      .members

    #expect(throws: SourceLayoutReplacementError.noncontiguousElements) {
      let layout = try Layout([members[0], members[2]]) {
        BlankLine(before: { _ in false })
      }
      let _: SourceFix = try #require(layout.correction.fix)
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
