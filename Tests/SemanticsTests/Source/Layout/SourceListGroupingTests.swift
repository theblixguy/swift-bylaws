import BylawsSemantics
import Testing

@Suite("Source list grouping")
struct SourceListGroupingTests {
  @Test("First matching group claims each element once")
  func firstMatch() throws {
    let file = try collect("""
    struct Store {
      let zebra = 1
      let apple = 2
      let banana = 3
    }
    """)
    let members = try #require(file.syntaxNodes(of: .structDeclaration).first)
      .members
    let fixLayout = try Layout(members) {
      Group { $0.name == "apple" }
      Group {
        if $0.name == "apple" { throw MockError.claimedElement }
        return true
      }
    }
    let fix: SourceFix = try #require(fixLayout.correction.fix)

    #expect(try applying(fix, to: file) == """
    struct Store {
      let apple = 2
      let zebra = 1
      let banana = 3
    }
    """)
  }

  @Test("Groups retain source order within each match")
  func stableGroups() throws {
    let file = try collect("""
    struct Store {
      var zebra = 1
      let pear = 2
      var apple = 3
      let banana = 4
    }
    """)
    let members = try #require(file.syntaxNodes(of: .structDeclaration).first)
      .members
    let fixLayout = try Layout(members) {
      Group { $0.property?.isConstant == true }
      BlankLine()
      Group { _ in true }
    }
    let fix: SourceFix = try #require(fixLayout.correction.fix)

    #expect(try applying(fix, to: file) == """
    struct Store {
      let pear = 2
      let banana = 4

      var zebra = 1
      var apple = 3
    }
    """)
  }

  @Test(
    "Groups apply ascending, descending and custom comparisons",
    arguments: [
      SortOrder.ascending,
      .descending,
      .length,
    ]
  )
  func comparison(_ order: SortOrder) throws {
    let file = try collect("""
    struct Store {
      let zebra = 1
      let a = 2
      let pear = 3
      let kiwi = 4
    }
    """)
    let members = try #require(file.syntaxNodes(of: .structDeclaration).first)
      .members
    let fixLayout = try Layout(members) {
      Group { _ in true }.sorted {
        let left = $0.name ?? ""
        let right = $1.name ?? ""
        return switch order {
        case .ascending: left < right
        case .descending: left > right
        case .length: left.count < right.count
        }
      }
    }
    let fix: SourceFix = try #require(fixLayout.correction.fix)
    let expected = switch order {
    case .ascending:
      "struct Store {\n  let a = 2\n  let kiwi = 4\n  let pear = 3\n  let zebra = 1\n}"
    case .descending:
      "struct Store {\n  let zebra = 1\n  let pear = 3\n  let kiwi = 4\n  let a = 2\n}"
    case .length:
      "struct Store {\n  let a = 2\n  let pear = 3\n  let kiwi = 4\n  let zebra = 1\n}"
    }
    let corrected = try applying(fix, to: file)
    let parsed = try collect(corrected)
    let declaration = try #require(parsed.syntaxNodes(of: .structDeclaration)
      .first)
    let secondLayout = try Layout(declaration.members) {
      Group { _ in true }.sorted {
        let left = $0.name ?? ""
        let right = $1.name ?? ""
        return switch order {
        case .ascending: left < right
        case .descending: left > right
        case .length: left.count < right.count
        }
      }
    }
    let second: SourceFix = try #require(secondLayout.correction.fix)

    #expect(corrected == expected)
    #expect(second.edits.isEmpty)
  }

  @Test("Attribute groups retain declaration boundaries")
  func attributeGroups() throws {
    let file = try collect("@Zebra @Apple class Store {}")
    let attributes = try #require(file.classes.first).attributes
    let fixLayout = try Layout(attributes) {
      Group { _ in true }.sorted { $0.name < $1.name }
    }
    let fix: SourceFix = try #require(fixLayout.correction.fix)

    #expect(try applying(fix, to: file) == "@Apple @Zebra class Store {}")
  }

  @Test("Argument groups retain commas around unmatched anchors")
  func argumentGroups() throws {
    let file =
      try collect(
        "let value = send(zebra: 1, apple: 2, marker: 0, pear: 3, banana: 4)"
      )
    let arguments = try #require(file.calls.first).arguments
    let fixLayout = try Layout(arguments) {
      Group { $0.label != "marker" }
        .sorted { ($0.label ?? "") < ($1.label ?? "") }
    }
    let fix: SourceFix = try #require(fixLayout.correction.fix)

    #expect(try applying(fix, to: file) ==
      "let value = send(apple: 2, zebra: 1, marker: 0, banana: 4, pear: 3)")
  }

  @Test("Unmatched declarations anchor separately sorted runs")
  func unmatchedAnchors() throws {
    let source = """
    struct Store {
      let zebra = 1
      let apple = 2


      var marker = 0

      let pear = 3
      let banana = 4
    }
    """
    let file = try collect(source)
    let members = try #require(file.syntaxNodes(of: .structDeclaration).first)
      .members
    let fixLayout = try Layout(members) {
      Group { $0.property?.isConstant == true }
        .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
    let fix: SourceFix = try #require(fixLayout.correction.fix)

    #expect(try applying(fix, to: file) == """
    struct Store {
      let apple = 2
      let zebra = 1


      var marker = 0

      let banana = 4
      let pear = 3
    }
    """)
  }

  @Test("Comparisons stay within runs separated by unmatched elements")
  func regionalComparisons() throws {
    let file = try collect("""
    struct Store {
      let zebra = 1
      let apple = 2
      var marker = 0
      let pear = 3
      let banana = 4
    }
    """)
    let members = try #require(file.syntaxNodes(of: .structDeclaration).first)
      .members
    let firstRun = ["zebra", "apple"]
    let fixLayout = try Layout(members) {
      Group { $0.property?.isConstant == true }.sorted {
        let left = $0.name ?? ""
        let right = $1.name ?? ""
        guard firstRun.contains(left) == firstRun.contains(right) else {
          throw MockError.claimedElement
        }
        return left < right
      }
    }
    let fix = try #require(fixLayout.correction.fix)

    #expect(try applying(fix, to: file) == """
    struct Store {
      let apple = 2
      let zebra = 1
      var marker = 0
      let banana = 4
      let pear = 3
    }
    """)
  }

  @Test("Empty groups add gaps only between populated groups")
  func emptyGroups() throws {
    let file = try collect("""
    struct Store {
      let zebra = 1
      let apple = 2
    }
    """)
    let members = try #require(file.syntaxNodes(of: .structDeclaration).first)
      .members
    let fixLayout = try Layout(members) {
      BlankLine()
      Group { _ in false }
      BlankLine()
      Group { $0.name == "apple" }
      BlankLine()
      Group { _ in false }
      BlankLine()
      Group { _ in true }
      BlankLine()
    }
    let fix: SourceFix = try #require(fixLayout.correction.fix)

    #expect(try applying(fix, to: file) == """
    struct Store {
      let apple = 2

      let zebra = 1
    }
    """)
  }

  @Test("Empty selections produce no edits")
  func emptySelection() throws {
    let members: [SourceNode] = []
    let layout = try Layout(members) {
      Group { _ in true }
    }

    #expect(layout.correction.outcome == .notApplicable)
    #expect(layout.correction.fix == nil)
  }

  @Test("Predicate and comparison errors propagate")
  func policyErrors() throws {
    let file =
      try collect("struct Store {\n  let first = 1\n  let second = 2\n}")
    let members = try #require(file.syntaxNodes(of: .structDeclaration).first)
      .members

    #expect(throws: MockError.claimedElement) {
      let layout = try Layout(members) {
        Group { _ in throw MockError.claimedElement }
      }
      let _: SourceFix = try #require(layout.correction.fix)
    }
    #expect(throws: MockError.claimedElement) {
      let layout = try Layout(members) {
        Group { _ in true }.sorted { _, _ in
          throw MockError.claimedElement
        }
      }
      let _: SourceFix = try #require(layout.correction.fix)
    }
  }

  enum SortOrder: Sendable {
    case ascending, descending, length
  }

  private enum MockError: Error, Equatable {
    case claimedElement
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
