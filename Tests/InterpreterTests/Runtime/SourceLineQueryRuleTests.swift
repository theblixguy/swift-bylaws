import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import Testing

@Suite("Portable source line widths")
struct SourceLineQueryRuleTests {
  @Test("Line limits include prefixes and suffixes", arguments: [
    ("let value = send(1, 2)", 21, 1),
    ("let value = send(1, 2)", 22, 0),
    ("let value = send(1, 2)", 23, 0),
    ("send(1, 2) // note", 17, 1),
    ("send(1, 2) // note", 18, 0),
    ("send(1, 2) // note", 19, 0),
  ])
  func surroundingText(
    source: String, limit: Int, expectedCount: Int
  ) async throws {
    let result = try await findings(source: source, limit: limit)

    #expect(result.violations.count == expectedCount)
    if expectedCount == 1 {
      let fix = try #require(result.violations.fixes.first ?? nil)
      #expect(try correctedSource(applying: fix) ==
        "func run() {\n\(source.replacing("send", with: "deliver"))\n}")
    }
  }

  @Test("Portable tabs use configured stops", arguments: [
    (8, 17, 1), (8, 18, 0),
    (4, 13, 1), (4, 14, 0),
    (0, 10, 1), (0, 11, 0),
  ])
  func tabs(tabWidth: Int, limit: Int, expectedCount: Int) async throws {
    let result = try await findings(
      source: "\tsend(1, 2)", limit: limit, tabWidth: tabWidth
    )

    #expect(result.violations.count == expectedCount)
  }

  @Test("Portable widths count characters", arguments: [
    ("let café = send(1, 2)", 20, 1),
    ("let café = send(1, 2)", 21, 0),
    ("send(1, 2) // 👩🏽‍💻", 14, 1),
    ("send(1, 2) // 👩🏽‍💻", 15, 0),
  ])
  func characters(
    source: String, limit: Int, expectedCount: Int
  ) async throws {
    let result = try await findings(source: source, limit: limit)

    #expect(result.violations.count == expectedCount)
  }

  @Test("Untouched lines stay outside portable query", arguments: [
    "\n", "\r\n", "\r",
  ])
  func lineEndings(ending: String) async throws {
    let result = try await findings(
      source: "longBefore()\(ending)send(1, 2)\(ending)longAfter()",
      limit: 10
    )

    #expect(result.violations.isEmpty)
  }

  @Test("Short multiline calls produce no correction")
  func multiline() async throws {
    let result = try await findings(
      source: "send(\n  first: 1,\n  second: 2\n)",
      limit: 12
    )

    #expect(result.violations.isEmpty)
  }

  @Test("Source projection selects queried lines", arguments: [
    ("calledExpressionSource", 0), ("source", 1),
  ])
  func projection(sourceMember: String, expectedCount: Int) async throws {
    let result = try await findings(
      source: "send(1, 2) {\n  consumeLongArgument(value: 123456)\n}",
      limit: 20,
      sourceMember: sourceMember
    )

    #expect(result.violations.count == expectedCount)
  }

  private func findings(
    source: String,
    limit: Int,
    tabWidth: Int? = nil,
    sourceMember: String = "source"
  ) async throws -> Rule.Findings {
    let tabArgument = tabWidth.map { ", tabWidth: \($0)" } ?? ""
    let project = try rulesProject(
      rules: """
      Rule("line-width") {
        try await app.calls.named("send").violations("Use shorter call name") { call in
          let source = try call.\(sourceMember)
          if source.hasLine(exceeding: \(limit)\(tabArgument)) {
            try call.calledExpressionSource.replacement(with: "deliver")
          }
        }
      }
      """,
      sources: ["Sources/App.swift": "func run() {\n\(source)\n}"]
    )
    let program = try await loadedProgram(in: project)
    return try await #require(program.rules.first).findings()
  }
}
