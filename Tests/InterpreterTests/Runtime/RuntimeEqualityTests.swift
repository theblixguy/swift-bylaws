import BylawsCore
import BylawsInterpreter
import Testing

@Suite("Portable model equality")
struct RuntimeEqualityTests {
  @Test("Model comparisons match native Swift", arguments: [
    "$0 == $0",
    "[$0].contains($0)",
    "Set([$0, $0]).count == 1",
    "[$0] == [$0]",
  ])
  func modelEquality(_ expression: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("equality") {
        app.structs.violations(of: Matcher<Struct>("compare equal") {
          \(expression)
        })
      }
      """,
      sources: ["Sources/Model.swift": "struct Model {}"]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    #expect(findings.violations.isEmpty)

    let models = try await Codebase(root: .sources([
      "Sources/Model.swift": "struct Model {}",
    ])).structs
    let model = try #require(models.first)
    #expect(model == model)
    #expect([model].contains(model))
    #expect(Set([model, model]).count == 1)
  }

  @Test("Loading rejects function comparisons", arguments: [
    "check == check", "[check] == [check]", "[check].contains(check)",
  ])
  func functionComparison(_ expression: String) async throws {
    let (program, project) = try await diagnostics(forRules: """
    func check(_ value: Int) -> Bool { value > 0 }
    let equal = \(expression)
    \(finalClassRuleSource)
    """)
    withExtendedLifetime(project) {
      #expect(program.errors.contains { $0.message.contains("cannot compare") })
    }
  }

  @Test("Set rejects function elements")
  func functionSet() async throws {
    let (program, project) = try await diagnostics(forRules: """
    func check(_ value: Int) -> Bool { value > 0 }
    let values = Set([check])
    \(finalClassRuleSource)
    """)
    withExtendedLifetime(project) {
      #expect(program.errors
        .contains { $0.message == "Set cannot contain a function" })
    }
  }
}
