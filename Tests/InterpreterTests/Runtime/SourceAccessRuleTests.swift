import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable source access")
struct SourceAccessRuleTests {
  @Test("Token spacing leaves operators inside strings and comments unchanged")
  func operators() async throws {
    try await check(
      rule: """
      Rule("operators") {
        try await app.files.violations("Space addition operators") { file in
          for token in try file.tokens {
            if token.kind == .binaryOperator && token.text == "+" {
              try token.spacing.before.replacement(with: .space)
              try token.spacing.after.replacement(with: .space)
            }
          }
        }
      }
      """,
      source: #"let café = left+right; let text = "a+b" // c+d"#,
      expected: #"let café = left + right; let text = "a+b" // c+d"#
    )
  }

  @Test(
    "Trivia corrections include file-end comments and exclude string content"
  )
  func comments() async throws {
    try await check(
      rule: #"""
      Rule("comments") {
        try await app.files.violations("Space TODO comments") { file in
          for comment in try file.trivia {
            if comment.kind == .lineComment && comment.isComment {
              for part in comment.source.matches(of: /^\/\/TODO:/) {
                part.replacement(with: "// TODO:")
              }
            }
          }
        }
      }
      """#,
      source: #"let text = "//TODO: preserved" //TODO: update"#,
      expected: #"let text = "//TODO: preserved" // TODO: update"#
    )
  }

  @Test("Token neighbours remain in the captured file")
  func neighbours() async throws {
    try await check(
      rule: """
      Rule("else") {
        try await app.files.violations("Place else after its closing brace") { file in
          for token in try file.tokens {
            if token.kind == .keyword && token.text == "else"
              && token.previous?.kind == .rightBrace {
              try token.spacing.before.replacement(with: .space)
            }
          }
        }
      }
      """,
      source: "if ready { run() }\nelse { wait() }",
      expected: "if ready { run() } else { wait() }"
    )
  }

  @Test("Canonical conditions use the shared layout builder")
  func conditions() async throws {
    try await check(
      rule: """
      Rule("conditions") {
        try await app.syntaxNodes(of: .conditionList).violations("Align conditions") { list in
          if !list.elements.isEmpty {
            try list.elements.replacement {
              Align { Wrap(width: 20) { list.elements } }
            }
          }
        }
      }
      """,
      source: "if firstCondition, secondCondition {}",
      expected: "if firstCondition,\n   secondCondition {}"
    )
  }

  @Test("Nested source replacements compose several original edits")
  func composition() async throws {
    try await check(
      rule: """
      Rule("calls") {
        try await app.calls.named("send").violations("Use named constants") { call in
          if call.arguments.count == 2 {
            let first = call.arguments[0]
            let second = call.arguments[1]
            try call.source.replacement(applying: [
              try first.expressionSource.replacement(with: "firstValue"),
              try second.expressionSource.replacement(with: "secondValue")
            ])
          }
        }
      }
      """,
      source: "let result = send(1, 2)",
      expected: "let result = send(firstValue, secondValue)"
    )
  }

  @Test("Contains matches self and descendant syntax", arguments: [
    (SourceNode.Kind.functionCall, SourceNode.Kind.functionCall, 0),
    (.codeBlock, .functionCall, 0),
    (.codeBlock, .variableDeclaration, 1),
  ])
  func contains(
    selection: SourceNode.Kind,
    target: SourceNode.Kind,
    expectedViolations: Int
  ) async throws {
    let project = try rulesProject(rules: """
    Rule("calls") {
      try await app.syntaxNodes(of: .\(selection.rawValue)).violations(of: Matcher<SourceNode>("contain requested syntax") {
        $0.contains(.\(target.rawValue))
      })
    }
    """, sources: ["Sources/App.swift": "func run() { send(1) }"])
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.checkedCount == 1)
    #expect(findings.violations.count == expectedViolations)
  }

  private func check(
    rule: String,
    source: String,
    expected: String
  ) async throws {
    let project = try rulesProject(
      rules: rule,
      sources: ["Sources/App.swift": source]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let edits = try #require(findings.violations.fixes.first ?? nil).edits
    var bytes = Array(source.utf8)
    for edit in edits
      .sorted(by: { $0.source.range.lowerBound > $1.source.range.lowerBound })
    {
      bytes.replaceSubrange(edit.source.range, with: edit.replacement.utf8)
    }
    let corrected = String(decoding: bytes, as: UTF8.self)
    #expect(corrected == expected)

    try corrected.write(
      to: project.fileURL(for: "Sources/App.swift"),
      atomically: true,
      encoding: .utf8
    )
    await CodebaseCache.shared.removeEntries(under: project.rootURL.path)
    let repeated = try await loadedProgram(in: project)
    #expect(try await #require(repeated.rules.first).findings().violations
      .isEmpty)
  }
}
