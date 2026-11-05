import Foundation
import Testing

@Suite("Portable CLI structural corrections")
struct CLIStructuralCorrectionProcessTests {
  @Test("Structural correction writes else-if and passes second run")
  func elseIf() throws {
    let project = try CLIProcessProject(
      source: """
      func choose() -> Int {
        if first { return 1 } else {
          if second { return 2 } else { return 3 }
        }
      }
      """,
      rules: """
      let app = Codebase(including: ["Sources/**"])
      Rule("branches") {
        try await app.ifExpressions.violations("Use else if") { conditional in
          try Unwrap(conditional.elseBody, containingOnly: .ifExpression)
        }
      }
      """
    )
    let sourceURL = project.root.appendingPathComponent("Sources/App/App.swift")
    let correction = try project.run("--autocorrect")

    #expect(correction.status == 0)
    #expect(correction.standardError.contains("Corrected 1 file:"))
    #expect(try Data(contentsOf: sourceURL) == Data("""
    func choose() -> Int {
      if first { return 1 } else if second { return 2 } else { return 3 }
    }
    """.utf8))

    let repeated = try project.run()

    #expect(repeated.status == 0)
    #expect(repeated.standardOutput.contains("Checked 1 rule: 0 violations."))
    #expect(repeated.standardError.isEmpty)
  }

  @Test("Portable list insertion and removal write source and pass rerun")
  func listEdits() throws {
    let project = try CLIProcessProject(
      source: "let result = send(old: 1, keep: 2)\n",
      rules: """
      let app = Codebase(including: ["Sources/**"])
      Rule("arguments") {
        try await app.calls.named("send").violations("Use current argument") { call in
          let arguments = try call.argumentList
          for argument in arguments {
            if argument.label == "old" {
              try Remove(argument)
              try Insert("current: 3", into: arguments, at: .start)
            }
          }
        }
      }
      """
    )
    let expected = Data("let result = send(current: 3, keep: 2)\n".utf8)
    let sourceURL = project.root.appendingPathComponent("Sources/App/App.swift")
    let correction = try project.run("--autocorrect", "--format", "json")

    #expect(correction.status == 0)
    #expect(correction.standardError.contains("Corrected 1 file:"))
    #expect(try Data(contentsOf: sourceURL) == expected)

    let repeated = try project.run("--autocorrect", "--format", "json")

    #expect(repeated.status == 0)
    #expect(repeated.standardError.isEmpty)
    #expect(try Data(contentsOf: sourceURL) == expected)
    for result in [correction, repeated] {
      let report = try #require(JSONSerialization.jsonObject(
        with: Data(result.standardOutput.utf8)
      ) as? [String: Any])
      let summary = try #require(report["summary"] as? [String: Int])
      let rules = try #require(report["rules"] as? [[String: Any]])

      #expect(summary["checkedRules"] == 1)
      #expect(summary["violations"] == 0)
      #expect(rules.compactMap { $0["id"] as? String } == ["arguments"])
    }
  }
}
