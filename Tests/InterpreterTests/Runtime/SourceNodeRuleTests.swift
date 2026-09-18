import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import Foundation
import Testing

@Suite("Portable syntax checks")
struct SourceNodeRuleTests {
  @Test("Compiled and interpreted syntax rules report same call")
  func parity() async throws {
    let rulesFile = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Support/PortableSyntaxRules.swift")
    let program = await RuleProgram.loaded(fromFiles: [rulesFile.path])
    try program.requireNoDiagnostics()
    let interpretedRule = try #require(program.rules.first)
    let compiledRule = try #require(portableSyntaxRules.first)

    let interpreted = try await interpretedRule.findings()
    let compiled = try await compiledRule.findings()

    #expect(interpreted.violations == compiled.violations)
    #expect(interpreted.violations.count == 1)
    #expect(interpreted.violations.offenders.first?.location.line == 6)
  }

  @Test("Name filters reject syntax nodes")
  func nameFilters() async throws {
    let (program, _) = try await diagnostics(forRules: """
    import Bylaws

    let app = Codebase(including: ["Sources/**"])
    let match = Matcher<SourceNode>("match") { _ in true }

    let rules: [Rule] = [
      Rule("syntax", "Syntax names banned") {
        try await app.syntaxNodes(of: .functionCall)
          .named("call")
          .violations(matching: match)
      },
    ]
    """)

    #expect(program.errors.contains {
      $0.message == "'named' is not a supported member of SourceNode"
    })
    #expect(program.rules.isEmpty)
  }
}
