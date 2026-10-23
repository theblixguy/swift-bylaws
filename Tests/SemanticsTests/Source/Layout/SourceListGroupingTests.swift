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
    let fix: SourceFix = try members.replacement {
      Group(where: { $0.name == "apple" })
      Group(where: {
        if $0.name == "apple" { throw MockError.claimedElement }
        return true
      })
    }

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
    let fix: SourceFix = try members.replacement {
      Group(where: { $0.property?.isConstant == true })
      BlankLine()
      Group(where: { _ in true })
    }

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
    let fix: SourceFix = try members.replacement {
      Group(where: { _ in true }).sorted {
        let left = $0.name ?? ""
        let right = $1.name ?? ""
        return switch order {
        case .ascending: left < right
        case .descending: left > right
        case .length: left.count < right.count
        }
      }
    }
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
    let second: SourceFix = try declaration.members.replacement {
      Group(where: { _ in true }).sorted {
        let left = $0.name ?? ""
        let right = $1.name ?? ""
        return switch order {
        case .ascending: left < right
        case .descending: left > right
        case .length: left.count < right.count
        }
      }
    }

    #expect(corrected == expected)
    #expect(second.edits.isEmpty)
  }

  @Test("Attribute groups retain declaration boundaries")
  func attributeGroups() throws {
    let file = try collect("@Zebra @Apple class Store {}")
    let attributes = try #require(file.classes.first).attributes
    let fix: SourceFix = try attributes.replacement {
      Group(where: { _ in true }).sorted { $0.name < $1.name }
    }

    #expect(try applying(fix, to: file) == "@Apple @Zebra class Store {}")
  }

  @Test("Argument groups retain commas around unmatched anchors")
  func argumentGroups() throws {
    let file =
      try collect(
        "let value = send(zebra: 1, apple: 2, marker: 0, pear: 3, banana: 4)"
      )
    let arguments = try #require(file.calls.first).arguments
    let fix: SourceFix = try arguments.replacement {
      Group(where: { $0.label != "marker" })
        .sorted { ($0.label ?? "") < ($1.label ?? "") }
    }

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
    let fix: SourceFix = try members.replacement {
      Group(where: { $0.property?.isConstant == true })
        .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

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
    let fix = try members.replacement {
      Group(where: { $0.property?.isConstant == true }).sorted {
        let left = $0.name ?? ""
        let right = $1.name ?? ""
        guard firstRun.contains(left) == firstRun.contains(right) else {
          throw MockError.claimedElement
        }
        return left < right
      }
    }

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
    let fix: SourceFix = try members.replacement {
      BlankLine()
      Group(where: { _ in false })
      BlankLine()
      Group(where: { $0.name == "apple" })
      BlankLine()
      Group(where: { _ in false })
      BlankLine()
      Group(where: { _ in true })
      BlankLine()
    }

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
    let fix: SourceFix = try members.replacement {
      Group(where: { _ in true })
    }

    #expect(fix.edits.isEmpty)
  }

  @Test("Predicate and comparison errors propagate")
  func policyErrors() throws {
    let file =
      try collect("struct Store {\n  let first = 1\n  let second = 2\n}")
    let members = try #require(file.syntaxNodes(of: .structDeclaration).first)
      .members

    #expect(throws: MockError.claimedElement) {
      let _: SourceFix = try members.replacement {
        Group(where: { _ in throw MockError.claimedElement })
      }
    }
    #expect(throws: MockError.claimedElement) {
      let _: SourceFix = try members.replacement {
        Group(where: { _ in true }).sorted { _, _ in
          throw MockError.claimedElement
        }
      }
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
