import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable deferred line widths")
struct DeferredLineWidthTests {
  @Test("Width conditions use strict threshold", arguments: [
    ("!.maximumLineLength(...9)", "send(\n  1,\n  2\n)", 1),
    ("!.maximumLineLength(...10)", "send(1, 2)", 0),
    ("!.maximumLineLength(...11)", "send(1, 2)", 0),
    ("nil", "send(\n  1,\n  2\n)", 1),
  ])
  func threshold(
    width: String, expected: String, expectedCount: Int
  ) async throws {
    let result = try await findings(
      source: "send(1, 2)",
      argument: "when: \(width)"
    )
    let edits = result.violations.fixes.compactMap(\.self).flatMap(\.edits)
    let candidates = result.violations.layoutCandidates
    let first = try #require(edits.first ?? candidates.first)

    #expect(result.violations.count == expectedCount)
    #expect(try first.source.file.replacement(
      applying: edits, layoutCandidates: candidates
    ).replacement == "func run() {\n\(expected)\n}")
  }

  @Test("Omitted width preserves unconditional layout")
  func omittedWidth() async throws {
    let result = try await findings(source: "send(1, 2)", argument: "")
    let fix = try #require(result.violations.fixes.first ?? nil)

    #expect(try correctedSource(applying: fix) ==
      "func run() {\nsend(\n  1,\n  2\n)\n}")
  }

  @Test("Optional width values reach layout evaluator")
  func optionalWidth() async throws {
    let result = try await findings(
      source: "send(1, 2)", argument: "when: limit",
      declarations: "let limit: SourceLayoutCondition? = !.maximumLineLength(...9)"
    )
    let fix = try #require(result.violations.fixes.first ?? nil)

    #expect(try correctedSource(applying: fix) ==
      "func run() {\nsend(\n  1,\n  2\n)\n}")
  }

  @Test("Short multiline calls retain original layout", arguments: [
    "\n", "\r\n", "\r",
  ])
  func multiline(ending: String) async throws {
    let source = "send(\(ending)  first: 1,\(ending)  second: 2\(ending))"
    let result = try await findings(
      source: source, argument: "when: !.maximumLineLength(...12)"
    )

    #expect(result.violations.isEmpty)
    #expect(result.violations.fixes.isEmpty)
    let candidate = try #require(result.violations.layoutCandidates.first)
    #expect(candidate.source.text == candidate.replacement)
  }

  @Test("Findings and fixes retain dormant layouts", arguments: [
    ("check", 1),
    ("try await check.withFix { _ in [] }", 1),
    ("check.findings(reportedAt: files[0].location).violations", 1),
    ("check.findings(reportedAt: files[0].location).checks[0]", 1),
    ("check\ncheck", 2),
  ])
  func candidatePropagation(
    expression: String,
    expectedCount: Int
  ) async throws {
    let result = try await findings(
      source: "send(1, 2)", argument: "when: !.maximumLineLength(...10)",
      resultExpression: expression
    )
    let candidates = result.violations.layoutCandidates
    let file = try #require(candidates.first).source.file
    let number = try file.matches(of: /1/).only()
    let combined = try file.replacement(
      applying: [number.replacement(with: "longName")],
      layoutCandidates: candidates
    )

    #expect(result.violations.isEmpty)
    #expect(candidates.count == expectedCount)
    #expect(combined.replacement ==
      "func run() {\nsend(\n  longName,\n  2\n)\n}")
  }

  @Test("Passing groups retain context through portable correction builder")
  func groupedContext() async throws {
    let project = try rulesProject(
      rules: """
      Rule("groups") {
        try await app.structs.violations("Group properties") { declaration in
          try Layout(declaration.properties) {
            Group { _ in true }
          }
        }
      }
      """,
      sources: [
        "Sources/Panel.swift": "struct Panel {\n  let first = 1\n  let second = 2\n}",
      ]
    )
    let program = try await loadedProgram(in: project)
    let result = try await #require(program.rules.first).findings()

    #expect(result.violations.isEmpty)
    #expect(result.violations.fixes.isEmpty)
    #expect(result.violations.layoutCandidates.count == 1)
    let candidate = try #require(result.violations.layoutCandidates.first)
    try candidate.validateLayoutCandidate()
  }

  @Test("Automatic groups take line conditions", arguments: [
    (".maximumLineLength(1...)", 1), (".maximumLineLength(...1)", 0), (
      "nil",
      1
    ),
  ])
  func conditionalGroups(condition: String, count: Int) async throws {
    let source = "struct Panel {\n  let zebra = 1\n  let alpha = 2\n}"
    let project = try rulesProject(
      rules: """
      Rule("groups") {
        try await app.structs.violations("Order properties") { declaration in
          try Layout(declaration.properties, when: \(condition)) {
            Group { true }.sorted { $0.name < $1.name }
          }
        }
      }
      """, sources: ["Sources/Panel.swift": source]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    #expect(findings.violations.count == count)
    if count == 1 {
      let fix = try #require(findings.violations.fixes.first ?? nil)
      #expect(try correctedSource(applying: fix) ==
        "struct Panel {\n  let alpha = 2\n  let zebra = 1\n}")
    }
  }

  @Test("Unconditional groups reorder source")
  func unconditionalGroups() async throws {
    let project = try rulesProject(
      rules: """
      Rule("groups") {
        try await app.structs.violations("Order properties") { declaration in
          try Layout(declaration.properties) {
            Group { _ in true }.sorted { $0.name < $1.name }
          }
        }
      }
      """,
      sources: [
        "Sources/Panel.swift": "struct Panel {\n  let second = 2\n  let first = 1\n}",
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let fix = try #require(findings.violations.fixes.first ?? nil)

    #expect(findings.violations.count == 1)
    #expect(try correctedSource(applying: fix) ==
      "struct Panel {\n  let first = 1\n  let second = 2\n}")
  }

  private func findings(
    source: String,
    argument: String,
    declarations: String = "",
    resultExpression: String = "check"
  ) async throws -> Rule.Findings {
    let project = try rulesProject(
      rules: """
      Rule("calls") {
        \(declarations)
        let files = try await app.files
        let check = try await app.calls.violations("Place arguments on separate lines") { call in
          if !call.arguments.isEmpty {
            try call.arguments.replacement(\(argument)) {
              for argument in call.arguments {
                Line { argument }
              }
            }
          }
        }
        \(resultExpression)
      }
      """,
      sources: ["Sources/Calls.swift": "func run() {\n\(source)\n}"]
    )
    let program = try await loadedProgram(in: project)
    return try await #require(program.rules.first).findings()
  }
}
