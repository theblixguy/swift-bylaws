import BylawsCore
import BylawsInterpreter
import Foundation
import Testing

@Suite("Portable body checks")
struct BodyRuleTests {
  @Test(
    "Compiled and interpreted body rules report same violations",
    arguments: [0, 1, 2]
  )
  func parity(index: Int) async throws {
    let rulesFile = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Support/PortableBodyRules.swift")
    let program = await RuleProgram.loaded(fromFiles: [rulesFile.path])
    try #require(program.diagnostics.isEmpty, "\(program.diagnostics)")
    try #require(program.rules.count == 3)
    let interpreted = try await program.rules[index].findings()
    let compiled = try await bodyRules[index].findings()
    #expect(interpreted.violations == compiled.violations)
    #expect(interpreted.violations.count == 1)
  }
}
