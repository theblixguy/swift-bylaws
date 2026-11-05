import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable layout conditions")
struct LayoutConditionTests {
  @Test("Range bounds match native conditions", arguments: [
    ("10...10", SourceLayoutCondition.maximumLineLength(10...10), true),
    ("11...20", .maximumLineLength(11...20), false),
    ("10..<11", .maximumLineLength(10..<11), true),
    ("10..<10", .maximumLineLength(10..<10), false),
    ("10...", .maximumLineLength(10...), true),
    ("11...", .maximumLineLength(11...), false),
    ("...10", .maximumLineLength(...10), true),
    ("...9", .maximumLineLength(...9), false),
    ("..<11", .maximumLineLength(..<11), true),
    ("..<10", .maximumLineLength(..<10), false),
    ("(-20)...(-1)", .maximumLineLength((-20)...(-1)), false),
    ("(-1)...", .maximumLineLength((-1)...), true),
    ("...9223372036854775807", .maximumLineLength(...Int.max), true),
    ("9223372036854775807...", .maximumLineLength(Int.max...), false),
  ])
  func ranges(
    spelling: String, condition: SourceLayoutCondition, matches: Bool
  ) async throws {
    let source = "func run() {\nsend(1, 2)\n}"
    let expected = matches ? "func run() {\nsend(\n  1,\n  2\n)\n}" : source
    let file = try FileCollector.collect(
      source: source,
      path: "/virtual/Calls.swift"
    )
    let call = try #require(file.calls.first)
    let correction = try Layout(
      call.arguments,
      layout: Lines(call.arguments, boundaries: .newline),
      when: condition
    ).correction
    let fix = correction.fix
    let native = try file.source.replacement(
      applying: fix?.edits ?? [],
      layoutCandidates: fix?.layoutCandidates ?? []
    ).replacement
    let portable =
      try await corrected(condition: ".maximumLineLength(\(spelling))")

    #expect(native == expected)
    #expect(portable.source == expected)
    #expect(portable.count == (matches ? 1 : 0))
  }

  @Test("Stored and combined conditions preserve value semantics", arguments: [
    ("!.maximumLineLength(...9)", true),
    (".maximumLineLength(10...) && .maximumLineLength(..<11)", true),
    (".maximumLineLength(11...) || .maximumLineLength(...9)", false),
    ("!(.maximumLineLength(11...) || .maximumLineLength(...9))", true),
    ("SourceLayoutCondition.maximumLineLength(10...10)", true),
    ("nil", true),
  ])
  func combinations(expression: String, matches: Bool) async throws {
    let result = try await corrected(condition: expression, stored: true)

    #expect(result.count == (matches ? 1 : 0))
    #expect(result
      .source ==
      (matches ? "func run() {\nsend(\n  1,\n  2\n)\n}" :
        "func run() {\nsend(1, 2)\n}"))
  }

  @Test(
    "Collection replacement takes conditions and stored components",
    arguments: [
      "try call.arguments.replacement(when: .maximumLineLength(10...)) { Lines(call.arguments, boundaries: .newline) }",
      "try call.arguments.replacement(layout: Lines(call.arguments, boundaries: .newline), when: .maximumLineLength(10...))",
      "try Layout(call.arguments, when: .maximumLineLength(10...)) { Lines(boundaries: .newline) { call.arguments } }",
      "try Layout(call.arguments, layout: Lines(call.arguments, boundaries: Lines.Boundaries.newline), when: SourceLayoutCondition.maximumLineLength(10...))",
    ]
  )
  func replacement(expression: String) async throws {
    let result = try await corrected(expression: expression)

    #expect(result.count == 1)
    #expect(result.source == "func run() {\nsend(\n  1,\n  2\n)\n}")
  }

  @Test("Closed ranges supply Int indices in layout loops")
  func closedRangeIteration() async throws {
    let result = try await corrected(expression: """
    try Layout(call.arguments) {
      Newline()
      Lines {
        for index in 0...1 { call.arguments[index] }
      }
      Newline()
    }
    """)

    #expect(result.source == "func run() {\nsend(\n  1,\n  2\n)\n}")
    #expect(result.count == 1)
  }

  @Test(
    "Reversed ranges report a rule error",
    arguments: ["11...10", "11..<10"]
  )
  func reversedRanges(range: String) async throws {
    await #expect {
      try await corrected(condition: ".maximumLineLength(\(range))")
    } throws: { error in
      String(describing: error)
        .contains("a range must end at or after its start")
    }
  }

  @Test("Empty lists remain unchanged under negation")
  func empty() async throws {
    let result = try await corrected(
      condition: "!.maximumLineLength(...0)",
      source: "func run() { send() }"
    )

    #expect(result.count == 0)
    #expect(result.source == "func run() { send() }")
  }

  @Test(
    "Conditions reject non-range values",
    arguments: ["12", "\"wide\"", "true"]
  )
  func nonRange(value: String) async throws {
    let project = try correctionProject(ruleBody: """
    try await app.calls.violations("Separate arguments") { call in
      try Layout(call.arguments, when: .maximumLineLength(\(value))) { Lines(call.arguments) }
    }
    """)

    await expectCorrectionRejection(
      in: project,
      containing: "maximumLineLength takes one Int range",
      atLine: 6
    )
  }

  @Test("Conditions reject non-Int range bounds", arguments: [
    "\"a\"...\"z\"", "1.5..<2.5", "1.5...", "...2.5",
  ])
  func rangeTypes(value: String) async throws {
    let project = try correctionProject(ruleBody: """
    try await app.calls.violations("Separate arguments") { call in
      try Layout(call.arguments, when: .maximumLineLength(\(value))) { Lines(call.arguments) }
    }
    """)
    let program = await RuleProgram
      .loaded(fromFiles: [project.fileURL(for: "ProjectRules.swift").path])

    #expect(program.rules.isEmpty)
    #expect(!program.errors.isEmpty)
  }

  @Test("Structural operations reject layout conditions", arguments: [
    "Replace(call, with: call, when: .maximumLineLength(10...))",
    "Unwrap(call, when: .maximumLineLength(10...))",
  ])
  func structuralCondition(operation: String) async throws {
    let project = try correctionProject(ruleBody: """
    try await app.calls.violations("Update calls") { call in
      try \(operation)
    }
    """)
    let program = await RuleProgram
      .loaded(fromFiles: [project.fileURL(for: "ProjectRules.swift").path])

    #expect(program.rules.isEmpty)
    #expect(program.errors.contains { $0.message.contains("takes") })
  }

  private func corrected(
    condition: String = "nil", stored: Bool = false,
    source: String = "func run() {\nsend(1, 2)\n}", expression: String? = nil
  ) async throws -> (source: String, count: Int) {
    let operation = expression ?? "try Layout(call.arguments, layout: Lines(call.arguments, boundaries: .newline), when: condition)"
    let project = try rulesProject(rules: """
    Rule("arguments") {
      let condition: SourceLayoutCondition? = \(condition)
      try await app.calls.violations("Separate arguments") { call in
        \(stored ? "let layout = Lines(call.arguments, boundaries: .newline)\ntry Layout(call.arguments, layout: layout, when: condition)" : operation)
      }
    }
    """, sources: ["Sources/Calls.swift": source])
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let fixes = findings.violations.fixes.compactMap(\.self)
    let edits = fixes.flatMap(\.edits)
    let candidates = findings.violations.layoutCandidates + fixes
      .flatMap(\.layoutCandidates)
    guard let region = edits.first ?? candidates.first else { return (
      source,
      findings.violations.count
    ) }
    return (
      try region.source.file
        .replacement(applying: edits, layoutCandidates: candidates).replacement,
      findings.violations.count
    )
  }
}
