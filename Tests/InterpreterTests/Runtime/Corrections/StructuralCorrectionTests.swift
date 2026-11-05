import Bylaws
import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Testing

@Suite("Portable structural corrections")
struct StructuralCorrectionTests {
  @Test("Whitespace replacements match native corrections", arguments: [
    (SourceWhitespace.none, ""), (.space, " "),
    (.newline, "\n   "), (.blankLine, "\n\n   "),
  ])
  func whitespaceReplacement(
    testCase: (whitespace: SourceWhitespace, separator: String)
  ) async throws {
    let source = "   class Store {}"
    let expected = "\(testCase.separator)class Store {}"
    let file = try FileCollector.collect(
      source: source, path: "/virtual/Store.swift"
    )
    let declaration = try #require(file.classes.first)
    let correction = try Replace(
      declaration.spacing.before, with: testCase.whitespace
    ).correction
    let fix = try #require(correction.fix)
    let project = try rulesProject(
      rules: """
      Rule("spacing") {
        try await app.classes.violations("Use declaration spacing") { declaration in
          try Replace(declaration.spacing.before, with: .\(testCase.whitespace.rawValue))
        }
      }
      """,
      sources: ["Sources/Store.swift": source]
    )

    #expect(try file.source.replacement(applying: fix.edits)
      .replacement == expected)
    #expect(try await corrected(project) == expected)
  }

  @Test(
    "Whitespace replacements reject non-slice targets",
    arguments: SourceWhitespace.allCases
  )
  func whitespaceTarget(whitespace: SourceWhitespace) async throws {
    let project = try correctionProject(ruleBody: """
    try await app.classes.violations("Use declaration spacing") { declaration in
      try Replace(declaration, with: .\(whitespace.rawValue))
    }
    """)

    await expectCorrectionRejection(
      in: project,
      containing: "Replace takes a SourceSlice for whitespace replacement",
      atLine: 6
    )
  }

  @Test("Else-if selection combines nested corrections", arguments: [
    "try Unwrap(conditional.elseBody, containingOnly: .ifExpression)",
    "if let body = conditional.elseBody { try body.unwrapped(containingOnly: .ifExpression) }",
    "if let body = conditional.elseBody { try body.source.unwrapped(containingOnly: .ifExpression) }",
  ])
  func elseIf(operation: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("branches") {
        try await app.ifExpressions.violations("Use else if") { conditional in
          \(operation)
        }
      }
      """,
      sources: [
        "Sources/Flow.swift": "func run() { if first {} else { if second {} else { if third {} } } }",
      ]
    )

    #expect(try await corrected(project) ==
      "func run() { if first {} else if second {} else if third {} }")
  }

  @Test("Captured replacement retains expression grouping", arguments: [
    "try Replace(call, with: argument.expressionSource)",
    "try Replace(call) { try argument.expressionSource }",
    "let content = try SourceReplacement { try argument.expressionSource }; try Replace(call, with: content)",
    "let content = try SourceReplacement(source: argument.expressionSource); try Replace(call, with: content)",
    "try call.source.replacement(with: argument.expressionSource)",
  ])
  func capturedReplacement(operation: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("identity") {
        try await app.calls.named("identity")
          .violations("Remove identity") { call in
            let argument = try call.arguments.only()
            \(operation)
          }
      }
      """,
      sources: [
        "Sources/Flow.swift": "let total = identity(left + right) * scale",
      ]
    )

    #expect(try await corrected(project) ==
      "let total = (left + right) * scale")
  }

  @Test("Scope keeps retained statements together", arguments: [
    "try Replace(conditional) { Scope { conditional.body.statements } }",
    "try Replace(conditional) { try Scope { try conditional.body.statementList } }",
    "let contents = SourceReplacement(sources: conditional.body.statements); let scope = Scope(replacement: contents); try Replace(conditional, with: scope.replacement)",
    "let contents = SourceReplacement { conditional.body.statements }; let combined = SourceReplacement(combining: [contents]); try Replace(conditional) { Scope { combined } }",
  ])
  func scope(operation: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("feature") {
        try await app.ifExpressions.violations("Keep enabled branch") { conditional in
          \(operation)
        }
      }
      """,
      sources: ["Sources/Flow.swift": """
      func run() {
        if enabled {
          defer { finish() }
          work()
        }
        next()
      }
      """]
    )

    #expect(try await corrected(project) == """
    func run() {
      do {
        defer { finish() }
        work()
      }
      next()
    }
    """)
  }

  @Test("Unknown builder context does not pass")
  func builderContext() async throws {
    let project = try rulesProject(
      rules: """
      Rule("branches") {
        try await app.ifExpressions.violations("Use else if") { conditional in
          try Unwrap(conditional.elseBody, containingOnly: .ifExpression)
        }
      }
      """,
      sources: [
        "Sources/Flow.swift": "var body: some View { if first {} else { if second {} } }",
      ]
    )
    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)

    await #expect(throws: (any Error).self) { try await rule.findings() }
  }

  private func corrected(_ project: TemporaryProject) async throws -> String {
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let edits = findings.violations.fixes.compactMap(\.self).flatMap(\.edits)
    let file = try #require(edits.first).source.file
    return try file.replacement(applying: edits).replacement
  }
}
