import BylawsSemantics
import Testing

@Suite("Combined grouping and spacing policies")
struct CombinedLayoutPolicyTests {
  @Test("Spacing conditions use adjacent elements after sorting")
  func reorderedPairs() throws {
    let file = try collect("""
    struct Item {
      let apple = 1
      let cherry = 3
      let banana = 2
    }
    """)
    let members = try #require(file.syntaxNodes(of: .structDeclaration).first)
      .members
    let operation = try Layout(members) {
      Group { _ in true }.sorted { ($0.name ?? "") < ($1.name ?? "") }
      BlankLine(between: { $0.name == "apple" }, and: { $0.name == "banana" })
    }

    #expect(try applying(operation, to: file) == """
    struct Item {
      let apple = 1

      let banana = 2
      let cherry = 3
    }
    """)
  }

  @Test("Projected groups leave missing values as ordering boundaries")
  func projectedGroups() throws {
    let file = try collect("""
    struct Item {
      let first = 1
      private let second = 2
      func boundary() {}
      let third = 3
      private let fourth = 4
    }
    """)
    let members = try #require(file.syntaxNodes(of: .structDeclaration).first)
      .members
    let operation = try Layout(members) {
      Group(\.property) { $0.isConstant && $0.visibility == .private }
      Group(\.property) { $0.isConstant }
    }

    #expect(try applying(operation, to: file) == """
    struct Item {
      private let second = 2
      let first = 1
      func boundary() {}
      private let fourth = 4
      let third = 3
    }
    """)
  }

  @Test("Spacing can cross a group boundary without moving unmatched members")
  func unmatchedBoundary() throws {
    let file = try collect("""
    struct Item {
      let zebra = 1
      let apple = 2
      func boundary() {}


      let last = 3
    }
    """)
    let members = try #require(file.syntaxNodes(of: .structDeclaration).first)
      .members
    let operation = try Layout(members) {
      Group(\.property) { $0.isConstant }
        .sorted { ($0.name ?? "") < ($1.name ?? "") }
      BlankLine(before: { $0.name == "boundary" })
    }

    #expect(try applying(operation, to: file) == """
    struct Item {
      let apple = 2
      let zebra = 1

      func boundary() {}


      let last = 3
    }
    """)
  }

  @Test("Group separators and conditional separators must agree")
  func conflictingSpacing() throws {
    let file =
      try collect("struct Item {\n  let first = 1\n  let second = 2\n}")
    let members = try #require(file.syntaxNodes(of: .structDeclaration).first)
      .members

    #expect(throws: SourceListLayoutError.conflictingSeparators) {
      try Layout(members) {
        Group { $0.name == "first" }
        BlankLine()
        Group { _ in true }
        Newline(after: { $0.name == "first" })
      }
    }
  }

  @Test("Legacy policy builders also combine groups and spacing")
  func legacyBuilder() throws {
    let file =
      try collect("struct Item {\n  let second = 2\n  let first = 1\n}")
    let members = try #require(file.syntaxNodes(of: .structDeclaration).first)
      .members
    let fixLayout = try Layout(members) {
      Group { _ in true }.sorted { ($0.name ?? "") < ($1.name ?? "") }
      BlankLine(after: { $0.name == "first" })
    }
    let fix = try #require(fixLayout.correction.fix)

    #expect(try file.source.replacement(applying: fix.edits).replacement == """
    struct Item {
      let first = 1

      let second = 2
    }
    """)
  }

  private func collect(_ source: String) throws -> SourceFile {
    try FileCollector.collect(source: source, path: "/virtual/Policies.swift")
  }

  private func applying(
    _ operation: Layout<some Any>, to file: SourceFile
  ) throws -> String {
    let fix = try #require(operation.correction.fix)
    return try file.source.replacement(applying: fix.edits).replacement
  }
}
