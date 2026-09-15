import BylawsCore
import BylawsInterpreter
import Foundation
import Testing

@Suite("Portable compilation-branch checks")
struct CompilationRuleTests {
  @Test(
    "Compiled and interpreted branch rules report same violations",
    arguments: [
      (index: 0, count: 2),
      (index: 1, count: 1),
      (index: 2, count: 1),
    ]
  )
  func parity(index: Int, count: Int) async throws {
    let rulesFile = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Support/PortableCompilationRules.swift")
    let program = await RuleProgram.loaded(fromFiles: [rulesFile.path])
    try #require(program.diagnostics.isEmpty, "\(program.diagnostics)")
    try #require(program.rules.count == 3)
    let interpreted = try await program.rules[index].findings()
    let compiled = try await compilationRules[index].findings()
    #expect(interpreted.violations == compiled.violations)
    #expect(interpreted.violations.count == count)
  }
}
