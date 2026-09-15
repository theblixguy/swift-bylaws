import BylawsCore
import BylawsInterpreter
import Foundation
import Testing

@Suite("Portable expression checks")
struct ExpressionRuleTests {
  @Test(
    "Compiled and interpreted expression rules report same calls",
    arguments: [0, 1, 2]
  )
  func parity(index: Int) async throws {
    let rulesFile = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Support/PortableExpressionRules.swift")
    let program = await RuleProgram.loaded(fromFiles: [rulesFile.path])
    try #require(program.diagnostics.isEmpty, "\(program.diagnostics)")
    try #require(program.rules.count == 3)
    let interpreted = try await program.rules[index].findings()
    let compiled = try await expressionRules[index].findings()
    #expect(interpreted.violations == compiled.violations)
    #expect(interpreted.violations.count == 1)
  }
}
