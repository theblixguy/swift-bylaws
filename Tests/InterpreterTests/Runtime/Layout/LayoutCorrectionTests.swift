import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Testing

@Suite("Portable layout corrections")
struct LayoutCorrectionTests {
  @Test("Empty lists need no layout guard", arguments: [
    ("classes", "try Layout(value.attributes) { Line { value.attributes } }"),
    (
      "calls",
      "try Layout(value.arguments) { Align { Wrap(width: 80) { value.arguments } } }"
    ),
  ])
  func emptyLists(testCase: (selection: String, layout: String)) async throws {
    let project = try rulesProject(
      rules: """
      Rule("layout") {
        try await app.\(testCase.selection).violations("Arrange source") { value in
          \(testCase.layout)
        }
      }
      """,
      sources: ["Sources/Store.swift": "class Store { func run() { send() } }"]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.checkedCount == 1)
    #expect(findings.violations.isEmpty)
    #expect(findings.violations.fixes.isEmpty)
  }

  @Test("Group conditions match native property ordering", arguments: [
    "Group(\\.isConstant)",
    "Group(Matcher<Property>(\"Be constant\") { $0.isConstant })",
    "Group { $0.isConstant }", "Group({ $0.isConstant })",
  ])
  func groupConditions(group: String) async throws {
    let source = "struct Store {\n  var count = 0\n  let limit = 1\n}"
    let expected = "struct Store {\n  let limit = 1\n  var count = 0\n}"
    let file = try FileCollector.collect(
      source: source,
      path: "/virtual/Store.swift"
    )
    let properties = try #require(file.structs.first).properties
    let groups = [
      Group<Property>(\.isConstant),
      Group(Matcher<Property>("Be constant") { $0.isConstant }),
    ]
    for group in groups {
      let correction = try Layout(properties) {
        group
        Group { _ in true }
      }.correction
      let fix = try #require(correction.fix)
      #expect(try file.source.replacement(applying: fix.edits)
        .replacement == expected)
    }
    let project = try rulesProject(
      rules: """
      Rule("constants") {
        try await app.structs.violations("Constants precede variables") { declaration in
          try Layout(declaration.properties) {
            \(group)
            Group { true }
          }
        }
      }
      """,
      sources: ["Sources/Store.swift": source]
    )

    #expect(try await corrected(project) == expected)
  }

  @Test("Group key paths must return Bool", arguments: ["name", "property"])
  func groupKeyPathResult(member: String) async throws {
    let project = try correctionProject(ruleBody: """
    try await app.syntaxNodes(of: .classDeclaration).violations("Group members") { declaration in
      try Layout(declaration.members) { Group(\\.\(member)) }
    }
    """)

    await expectCorrectionRejection(
      in: project, containing: "the key path", atLine: 6
    )
  }

  @Test("Stored soft breaks match native layouts", arguments: [
    "SourceLayout.softBreak", ".softBreak",
  ])
  func storedSoftBreak(spelling: String) async throws {
    let source = "@Zebra\n@Apple\nclass Store {}"
    let expected = "@Apple @Zebra\nclass Store {}"
    let file = try FileCollector.collect(
      source: source, path: "/virtual/Store.swift"
    )
    let attributes = try #require(file.classes.first).attributes
    let layout = SourceLayout([
      SourceLayout(attributes[1]), SourceLayout.softBreak,
      SourceLayout(attributes[0]),
    ])
    let correction = try Layout(
      attributes, layout: Wrap(layout: layout, width: 100).layout
    ).correction
    let fix = try #require(correction.fix)
    let native = try file.source.replacement(
      applying: fix.edits, layoutCandidates: fix.layoutCandidates
    ).replacement
    let project = try rulesProject(
      rules: """
      Rule("attributes") {
        try await app.classes.violations("Order attributes") { declaration in
          let attributes = declaration.attributes
          let layout = SourceLayout([
            SourceLayout(attributes[1]), \(spelling),
            SourceLayout(attributes[0])
          ])
          try Layout(attributes, layout: Wrap(layout: layout, width: 100).layout)
        }
      }
      """,
      sources: ["Sources/Store.swift": source]
    )

    #expect(native == expected)
    #expect(try await corrected(project) == expected)
  }

  @Test("Stored and builder layouts defer nested width checks", arguments: [
    "try Layout(arguments, when: !.maximumLineLength(...30)) { Newline(); Lines { arguments }; Newline() }",
    "let rows = Lines(layout: SourceLayout(arguments)).layout; try Layout(arguments, layout: SourceLayout([.newline, rows, .newline]), when: !.maximumLineLength(...30))",
    "let rows = Lines { arguments }; try Layout(arguments, layout: SourceLayout([SourceLayout.newline, rows.layout, SourceLayout.newline]), when: !.maximumLineLength(...30))",
  ])
  func nestedCalls(operation: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("arguments") {
        try await app.calls.violations("Wrap long calls") { call in
          let arguments = try call.argumentList
          if arguments.count > 1 { \(operation) }
        }
      }
      """,
      sources: [
        "Sources/Calls.swift": "func run() {\n  send(first: 1, second: wrap(2, 3))\n}",
      ]
    )

    #expect(try await corrected(project) == """
    func run() {
      send(
        first: 1,
        second: wrap(2, 3)
      )
    }
    """)
  }

  @Test("Projected groups and matchers use final adjacent members", arguments: [
    "Group(\\.property) { $0.isConstant }",
    "Group(\\.property, where: \\.isConstant)",
    "Group(Matcher<SourceNode>(\"Be constant\") { $0.property?.isConstant == true })",
  ])
  func groupedMembers(group: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("members") {
        try await app.syntaxNodes(of: .structDeclaration).violations("Order constants") { declaration in
          try Layout(declaration.members) {
            \(group).sorted { ($0.name ?? "") < ($1.name ?? "") }
            BlankLine(between: { $0.name == "apple" }, and: { $0.name == "banana" })
          }
        }
      }
      """,
      sources: ["Sources/Item.swift": """
      struct Item {
        let apple = 1
        let cherry = 3
        let banana = 2
        func boundary() {}
      }
      """]
    )

    #expect(try await corrected(project) == """
    struct Item {
      let apple = 1

      let banana = 2
      let cherry = 3
      func boundary() {}
    }
    """)
  }

  @Test(
    "Stored policy values compose with builder policies",
    arguments: [false, true]
  )
  func storedPolicies(builder: Bool) async throws {
    let operation = builder
      ? "try Layout(declaration.members) { groups; BlankLine(before: { $0.name == \"second\" }) }"
      : "try Layout(declaration.members, layout: .sequence([groups, .blankLine(BlankLine(before: { $0.name == \"second\" }))]))"
    let project = try rulesProject(
      rules: """
      Rule("members") {
        try await app.syntaxNodes(of: .structDeclaration).violations("Group constants") { declaration in
          let groups = LayoutContent<SourceNode>.sequence([
            .group(Group(\\.property) { $0.visibility == .private }),
            .group(Group(\\.property) { $0.isConstant })
          ])
          \(operation)
        }
      }
      """,
      sources: [
        "Sources/Item.swift": "struct Item {\n  let second = 2\n  private let first = 1\n}",
      ]
    )

    #expect(try await corrected(project) ==
      "struct Item {\n  private let first = 1\n\n  let second = 2\n}")
  }

  @Test(
    "Conditional layouts respect the exact width limit",
    arguments: [9, 10, 11]
  )
  func policyWidth(limit: Int) async throws {
    let original = "func run() {\n  first()\n  second()\n}"
    let project = try rulesProject(
      rules: """
      Rule("statements") {
        try await app.syntaxNodes(of: .codeBlock).violations("Separate calls") { block in
          try Layout(block.statements, when: !.maximumLineLength(...\(limit))) {
            BlankLine(before: { $0.call != nil })
          }
        }
      }
      """,
      sources: ["Sources/Calls.swift": original]
    )

    if limit < 10 {
      #expect(try await corrected(project) ==
        "func run() {\n  first()\n\n  second()\n}")
    } else {
      let program = try await loadedProgram(in: project)
      #expect(try await #require(program.rules.first).findings().violations
        .isEmpty)
    }
  }

  @Test(
    "Unavailable nested corrections retain the offender without a partial fix"
  )
  func unavailableCorrection() async throws {
    let project = try rulesProject(
      rules: """
      Rule("arguments") {
        try await app.calls.violations("Arrange arguments") { call in
          try Layout(call.arguments) {
            call.arguments
            SourceCorrection.unavailable("The comment has no clear owner.")
          }
        }
      }
      """,
      sources: [
        "Sources/Calls.swift": "func run() { send(first: 1, second: 2) }",
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.count == 1)
    #expect(findings.violations.fixes == [nil])
  }

  @Test("Inactive layout branches leave nonempty lists unchanged", arguments: [
    "try Layout(call.arguments) { if false { Group { true } } }",
    "try Layout(call.arguments, layout: Lines { SourceLayout([]) }.layout)",
  ])
  func inactiveLayout(operation: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("arguments") {
        try await app.calls.violations("Retain arguments") { call in
          \(operation)
        }
      }
      """,
      sources: [
        "Sources/Calls.swift": "func run() { send(first: 1, second: 2) }",
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    #expect(findings.violations.checkedCount == 1)
    #expect(findings.violations.isEmpty)
  }

  @Test("Attribute matchers group syntax nodes")
  func attributeMatcher() async throws {
    let project = try rulesProject(
      rules: """
      Rule("members") {
        try await app.syntaxNodes(of: .structDeclaration).violations("Group state") { declaration in
          try Layout(declaration.members) {
            Group(.hasAttribute("State"))
            BlankLine()
            Group(\\.property) { $0.isConstant }
          }
        }
      }
      """,
      sources: [
        "Sources/Item.swift": "struct Item {\n  let count = 1\n  @State var selected = false\n}",
      ]
    )

    #expect(try await corrected(project) ==
      "struct Item {\n  @State var selected = false\n\n  let count = 1\n}")
  }

  @Test(
    "Unknown nested correction stops grouped and explicit layouts",
    arguments: [false, true]
  )
  func unknownOutcome(grouped: Bool) async throws {
    let layout = grouped ? "Group { true }" : "call.arguments"
    let project = try rulesProject(
      rules: """
      Rule("arguments") {
        try await app.calls.violations("Arrange arguments") { call in
          try Layout(call.arguments) {
            \(layout)
            SourceCorrection.unavailable("The comment has no clear owner.")
            SourceCorrection.undetermined("The enclosing context is unknown.")
          }
        }
      }
      """,
      sources: [
        "Sources/Calls.swift": "func run() { send(first: 1, second: 2) }",
      ]
    )
    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)

    await #expect {
      try await rule.findings()
    } throws: { error in
      String(describing: error).contains("The enclosing context is unknown.")
    }
  }

  private func corrected(_ project: TemporaryProject) async throws -> String {
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let edits = findings.violations.fixes.compactMap(\.self).flatMap(\.edits)
    let file = try #require(edits.first).source.file
    return try file.replacement(applying: edits).replacement
  }
}
