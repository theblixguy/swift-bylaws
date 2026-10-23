import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable automatic grouping")
struct AutomaticGroupingTests {
  @Test(
    "Groups retain unmatched declarations and use first matching membership"
  )
  func groupedMembers() async throws {
    let project = try rulesProject(
      rules: """
      Rule("members") {
        try await app.syntaxNodes(of: .structDeclaration).violations("Group properties") { declaration in
          try declaration.members.replacement {
            Group(where: { $0.hasAttribute("State") })
            BlankLine()
            Group(where: { $0.property?.visibility == .private })
            Group(where: { $0.property?.isConstant == true })
              .sorted { ($0.name ?? "") < ($1.name ?? "") }
          }
        }
      }
      """,
      sources: [
        "Sources/Panel.swift": """
        struct Panel {
          let zebra = 1
          @State private var query = ""
          private let store = Store()
          let alpha = 2
          func refresh() {}
          let count = 0
          @State private var selected = false
        }
        """,
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let fix = try #require(findings.violations.fixes.first ?? nil)
    let expected = """
    struct Panel {
      @State private var query = ""

      private let store = Store()
      let alpha = 2
      let zebra = 1
      func refresh() {}
      @State private var selected = false

      let count = 0
    }
    """

    #expect(try correctedSource(applying: fix) == expected)

    try expected.write(
      to: project.fileURL(for: "Sources/Panel.swift"), atomically: true,
      encoding: .utf8
    )
    await CodebaseCache.shared.removeEntries(under: project.rootURL.path)
    let corrected = try await loadedProgram(in: project)
    #expect(try await #require(corrected.rules.first).findings().violations
      .isEmpty)
  }

  @Test(
    "Empty automatic layouts and unmatched groups produce no correction",
    arguments: [
      "func run() {}",
      "func run() { send() }",
    ]
  )
  func unchanged(source: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("statements") {
        try await app.syntaxNodes(of: .codeBlock).violations("Group bindings") { block in
          try block.statements.replacement {
            Group(where: { $0.kind == .variableDeclaration })
            BlankLine()
            Group(where: { false })
          }
        }
      }
      """,
      sources: ["Sources/Calls.swift": source]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    #expect(findings.violations.isEmpty)
  }

  @Test("Groups skip later predicates for claimed elements")
  func claimedElements() async throws {
    let project = try rulesProject(
      rules: """
      Rule("statements") {
        try await app.syntaxNodes(of: .codeBlock).violations("Retain statements") { block in
          try block.statements.replacement {
            Group(where: { true })
            Group(where: {
              let region = try $0.source.slice(1000..<1001)
              return region.text.isEmpty
            })
          }
        }
      }
      """,
      sources: ["Sources/Calls.swift": "func run() {\n  send()\n}"]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    #expect(findings.violations.isEmpty)
  }

  @Test("Comparisons remain within matched regions")
  func comparisonRegions() async throws {
    let project = try rulesProject(
      rules: """
      Rule("members") {
        try await app.syntaxNodes(of: .structDeclaration).violations("Order constants") { declaration in
          try declaration.members.replacement {
            Group(where: { $0.property?.isConstant == true }).sorted {
              if $0.name == "first" || $1.name == "first" {
                let region = try $0.source.slice(1000..<1001)
                return region.text.isEmpty
              }
              return ($0.name ?? "") < ($1.name ?? "")
            }
          }
        }
      }
      """,
      sources: ["Sources/Panel.swift": """
      struct Panel {
        let first = 0
        func refresh() {}
        let zebra = 2
        let alpha = 1
      }
      """]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let fix = try #require(findings.violations.fixes.first ?? nil)
    #expect(try correctedSource(applying: fix) == """
    struct Panel {
      let first = 0
      func refresh() {}
      let alpha = 1
      let zebra = 2
    }
    """)
  }
}
