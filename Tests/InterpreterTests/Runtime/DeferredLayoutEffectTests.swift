import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable deferred layout effects")
struct DeferredLayoutEffectTests {
  enum Policy: CaseIterable {
    case groupPredicate
    case groupComparison
    case blankLine
    case newline
  }

  @Test(
    "Nonthrowing factories defer policy errors until replacement",
    arguments: Policy.allCases,
    [false, true]
  )
  func deferredEffects(policy: Policy, fails: Bool) async throws {
    let start = if fails { 1000 } else { 0 }
    let expression = switch policy {
    case .groupPredicate:
      """
      Group<SourceNode>(where: { node in
        let prefix = try node.source.slice(\(start)..<\(start + 1))
        return !prefix.text.isEmpty
      })
      """
    case .groupComparison:
      """
      Group<SourceNode>(where: { _ in true }).sorted { left, right in
        let prefix = try left.source.slice(\(start)..<\(start + 1))
        return !prefix.text.isEmpty && (left.name ?? "") < (right.name ?? "")
      }
      """
    case .blankLine:
      """
      BlankLine<SourceNode>(before: { node in
        let prefix = try node.source.slice(\(start)..<\(start + 1))
        return !prefix.text.isEmpty
      })
      """
    case .newline:
      """
      Newline<SourceNode>(after: { node in
        let prefix = try node.source.slice(\(start)..<\(start + 1))
        return !prefix.text.isEmpty
      })
      """
    }
    let resultType = switch policy {
    case .groupPredicate, .groupComparison: "Group<SourceNode>"
    case .blankLine: "BlankLine<SourceNode>"
    case .newline: "Newline<SourceNode>"
    }
    let project = try rulesProject(
      rules: """
      Rule("members") {
        try await app.syntaxNodes(of: .structDeclaration).violations("Arrange members") { declaration in
          try declaration.members.replacement {
            makePolicy()
          }
        }
      }
      """,
      sources: [
        "Sources/Panel.swift": "struct Panel {\n  let zebra = 1\n  let alpha = 2\n}",
      ]
    )
    let path = project.fileURL(for: "ProjectRules.swift")
    let originalRules = try String(contentsOf: path, encoding: .utf8)
    try """
    func makePolicy() -> \(resultType) {
      \(expression)
    }

    \(originalRules)
    """.write(to: path, atomically: true, encoding: .utf8)
    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)

    if fails {
      await #expect {
        try await rule.findings()
      } throws: { error in
        String(describing: error)
          .contains(SourceError.rangeOutOfBounds.description)
      }
    } else {
      let findings = try await rule.findings()
      switch policy {
      case .groupPredicate, .newline:
        #expect(findings.violations.isEmpty)
      case .groupComparison:
        let fix = try #require(findings.violations.fixes.first ?? nil)
        #expect(try correctedSource(applying: fix) ==
          "struct Panel {\n  let alpha = 2\n  let zebra = 1\n}")
      case .blankLine:
        let fix = try #require(findings.violations.fixes.first ?? nil)
        #expect(try correctedSource(applying: fix) ==
          "struct Panel {\n  let zebra = 1\n\n  let alpha = 2\n}")
      }
    }
  }

  @Test("Collection sorting propagates comparison errors to its caller")
  func immediateComparisonEffects() async throws {
    let project = try rulesProject(
      rules: """
      Rule("members") {
        try await app.structs.violations(of: .isPublic)
      }
      """,
      sources: ["Sources/Panel.swift": "struct Panel {}"]
    )
    let path = project.fileURL(for: "ProjectRules.swift")
    let originalRules = try String(contentsOf: path, encoding: .utf8)
    try """
    func ordered(_ members: [SourceNode]) -> [SourceNode] {
      members.sorted { left, right in
        let prefix = try left.source.slice(0..<1)
        return !prefix.text.isEmpty && (left.name ?? "") < (right.name ?? "")
      }
    }

    \(originalRules)
    """.write(to: path, atomically: true, encoding: .utf8)
    let program = await RuleProgram.loaded(fromFiles: [path.path])

    #expect(program.rules.isEmpty)
    #expect(program.errors.contains {
      $0.message.contains("a nonthrowing body cannot call a throwing API")
    })
  }
}
