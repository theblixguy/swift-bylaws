import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable conditional spacing")
struct ConditionalLayoutTests {
  @Test(
    "Conditional separators preserve unmatched gaps",
    arguments: ["\n", "\r\n", "\r"]
  )
  func statementSpacing(ending: String) async throws {
    let source = """
    func refresh() async throws {
      let request = try makeRequest()
      await record(request)
      try await save(request)
      let count = 1


      let limit = 2
    }
    """.replacing("\n", with: ending)
    let expected = """
    func refresh() async throws {
      let request = try makeRequest()

      await record(request)

      try await save(request)

      let count = 1


      let limit = 2
    }
    """.replacing("\n", with: ending)
    let project = try rulesProject(
      rules: """
      Rule("statements") {
        try await app.syntaxNodes(of: .codeBlock).violations("Separate statements") { block in
          try block.statements.replacement {
            BlankLine(between: { $0.kind == .variableDeclaration }, and: { $0.call != nil })
            BlankLine(between: { $0.contains(.tryExpression) }, and: {
              $0.kind == .variableDeclaration || $0.call != nil
            })
          }
        }
      }
      """,
      sources: ["Sources/Refresh.swift": source]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let fix = try #require(findings.violations.fixes.first ?? nil)

    #expect(try correctedSource(applying: fix) == expected)
  }

  @Test("Directional separators match the requested side", arguments: [
    (
      "BlankLine(before: { $0.call != nil })",
      "let value = 0\n\n  send()\n  let next = 1"
    ),
    (
      "BlankLine(after: { $0.call != nil })",
      "let value = 0\n  send()\n\n  let next = 1"
    ),
    (
      "Newline(before: { $0.call != nil })",
      "let value = 0\n  send()\n  let next = 1"
    ),
  ])
  func directionalSpacing(operation: String, body: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("statements") {
        try await app.syntaxNodes(of: .codeBlock).violations("Separate calls") { block in
          try block.statements.replacement {
            \(operation)
          }
        }
      }
      """,
      sources: [
        "Sources/Calls.swift": "func run() {\n  let value = 0\n  send()\n  let next = 1\n}",
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    if operation.hasPrefix("Newline") {
      #expect(findings.violations.isEmpty)
    } else {
      let fix = try #require(findings.violations.fixes.first ?? nil)
      #expect(try correctedSource(applying: fix) ==
        "func run() {\n  \(body)\n}")
    }
  }

  @Test("Conditional predicates must return Bool")
  func predicateType() async throws {
    let project = try rulesProject(
      rules: """
      Rule("statements") {
        try await app.syntaxNodes(of: .codeBlock).violations("Separate statements") { block in
          try block.statements.replacement {
            BlankLine(before: { $0.text })
          }
        }
      }
      """,
      sources: ["Sources/Calls.swift": "func run() {\n  send()\n}"]
    )
    let program = await RuleProgram
      .loaded(fromFiles: [project.fileURL(for: "ProjectRules.swift").path])
    #expect(program.rules.isEmpty)
    #expect(program.errors.contains { $0.message.contains("must be Bool") })
  }

  @Test(
    "Automatic layouts reject mixed source emission and conflicting policies",
    arguments: [
      (
        "Group(where: { true }); block.statements",
        "must contain groups and separators"
      ),
      (
        "Group(where: { true }); BlankLine(before: { true })",
        "must use grouping or conditional spacing"
      ),
      (
        "Newline(before: { true }); BlankLine(after: { true })",
        "must use one separator for each gap"
      ),
    ]
  )
  func conflictingPolicies(policy: String, message: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("statements") {
        try await app.syntaxNodes(of: .codeBlock).violations("Separate statements") { block in
          try block.statements.replacement {
            \(policy)
          }
        }
      }
      """,
      sources: ["Sources/Calls.swift": "func run() {\n  first()\n  second()\n}"]
    )
    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)

    await #expect {
      try await rule.findings()
    } throws: { error in
      String(describing: error).contains(message)
    }
  }
}
