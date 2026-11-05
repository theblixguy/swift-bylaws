import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable reusable layouts")
struct ReusableLayoutTests {
  @Test("Unused groups leave membership unchanged")
  func unusedGroup() async throws {
    let project = try rulesProject(
      rules: """
      Rule("members") {
        try await app.syntaxNodes(of: .structDeclaration).violations("Order members") { declaration in
          try Layout(declaration.members) {
            let unused = Group { true }
            Group { true }.sorted { ($0.name ?? "") < ($1.name ?? "") }
          }
        }
      }
      """,
      sources: [
        "Sources/Panel.swift": "struct Panel {\n  let zebra = 1\n  let alpha = 2\n}",
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let fix = try #require(findings.violations.fixes.first ?? nil)
    #expect(try correctedSource(applying: fix) ==
      "struct Panel {\n  let alpha = 2\n  let zebra = 1\n}")
  }

  @Test(
    "Inactive automatic policies retain their resolved layout kind",
    arguments: [
      "if false { Group { true } }",
      "if false { BlankLine(before: { $0.call != nil }) }",
      "for index in 0..<0 { Group { true } }",
    ],
    ["func run() {}", "func run() {\n  send()\n}"]
  )
  func inactivePolicies(policy: String, source: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("statements") {
        try await app.syntaxNodes(of: .codeBlock).violations("Retain statements") { block in
          try Layout(block.statements) {
            \(policy)
          }
        }
      }
      """,
      sources: ["Sources/Calls.swift": source]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    #expect(findings.violations.checkedCount == 1)
    #expect(findings.violations.isEmpty)
  }

  @Test(
    "Stored groups retain element types and inactive branches",
    arguments: [false, true]
  )
  func storedGroup(included: Bool) async throws {
    let project = try rulesProject(
      rules: """
      Rule("members") {
        try await app.syntaxNodes(of: .structDeclaration).violations("Order constants") { declaration in
          let constants = Group<SourceNode> { $0.property?.isConstant == true }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
          try Layout(declaration.members) {
            if \(included) { constants }
          }
        }
      }
      """,
      sources: [
        "Sources/Panel.swift": "struct Panel {\n  let zebra = 1\n  let alpha = 2\n}",
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    if included {
      let fix = try #require(findings.violations.fixes.first ?? nil)
      #expect(try correctedSource(applying: fix) ==
        "struct Panel {\n  let alpha = 2\n  let zebra = 1\n}")
    } else {
      #expect(findings.violations.checkedCount == 1)
      #expect(findings.violations.isEmpty)
    }
  }

  @Test(
    "Stored separators retain conditional element types",
    arguments: [false, true]
  )
  func storedSeparator(included: Bool) async throws {
    let project = try rulesProject(
      rules: """
      Rule("statements") {
        try await app.syntaxNodes(of: .codeBlock).violations("Separate calls") { block in
          let separator: BlankLine<SourceNode> = BlankLine<SourceNode>(before: { $0.call != nil })
          try Layout(block.statements) {
            if \(included) { separator }
          }
        }
      }
      """,
      sources: [
        "Sources/Calls.swift": "func run() {\n  let count = 1\n  send()\n}",
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    if included {
      let fix = try #require(findings.violations.fixes.first ?? nil)
      #expect(try correctedSource(applying: fix) ==
        "func run() {\n  let count = 1\n\n  send()\n}")
    } else {
      #expect(findings.violations.checkedCount == 1)
      #expect(findings.violations.isEmpty)
    }
  }

  @Test("Unused groups retain explicit source emission")
  func unusedGroupInExplicitLayout() async throws {
    let project = try rulesProject(
      rules: """
      Rule("members") {
        try await app.syntaxNodes(of: .structDeclaration).violations("Retain members") { declaration in
          try Layout(declaration.members) {
            let unused = Group<SourceNode> { true }
            declaration.members
          }
        }
      }
      """,
      sources: ["Sources/Panel.swift": "struct Panel {\n  let count = 0\n}"]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    #expect(findings.violations.checkedCount == 1)
    #expect(findings.violations.isEmpty)
  }
}

extension ReusableLayoutTests {
  @Test("Layout callbacks retain their element type", arguments: [false, true])
  func contentCallback(stored: Bool) async throws {
    let body = """
    .group(Group<Property> { _ in true }.sorted { $0.name < $1.name })
    """
    let declaration = stored
      ? "let ordering = { () -> LayoutContent<Property> in \(body) }"
      : "func ordering() -> LayoutContent<Property> { \(body) }"
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "Sources/Item.swift": "struct Item {\n  let zebra = 1\n  let apple = 2\n}",
      "ProjectRules.swift": """
      import Bylaws
      let app = Codebase(root: .automatic(), including: ["Sources/**"])
      \(declaration)
      let projectRules: [Rule] = [
        Rule("properties") {
          try await app.structs.violations("Order properties") { declaration in
            try Layout(declaration.properties, ordering)
          }
        }
      ]
      """,
    ])
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let fix = try #require(findings.violations.fixes.first ?? nil)

    #expect(try correctedSource(applying: fix) == """
    struct Item {
      let apple = 2
      let zebra = 1
    }
    """)
  }
}
