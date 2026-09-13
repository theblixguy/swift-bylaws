import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import Foundation
import Testing

@Suite("Portable interpreted rules")
struct PortableInterpreterTests {
  @Test("Compiled and interpreted forms of one rules file agree")
  func compiledAndInterpretedRules() async throws {
    let rulesFile = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Support/PortableRulesParity.swift")
    let program = await RuleProgram.loaded(fromFiles: [rulesFile.path])
    #expect(program.diagnostics.isEmpty)
    let interpretedRule = try #require(program.rules.first)
    let compiledRule = try #require(portableRules.first)

    let interpreted = try await interpretedRule.findings()
    let compiled = try await compiledRule.findings()

    #expect(interpretedRule.id == compiledRule.id)
    #expect(interpretedRule.name == compiledRule.name)
    #expect(interpretedRule.enforcement == compiledRule.enforcement)
    #expect(interpretedRule.hint == compiledRule.hint)
    #expect(interpreted.violations == compiled.violations)
    #expect(interpreted.warnings == compiled.warnings)
    #expect(interpreted.violations.count == 2)
  }
}
