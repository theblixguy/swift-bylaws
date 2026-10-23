import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable condition sequences")
struct RuntimeConditionTests {
  @Test("Boolean conditions stop before unsafe later expressions")
  func booleanConditions() async throws {
    try await check(
      declarations: """
      func startsWithOne(_ values: [Int]) -> Bool {
        if !values.isEmpty, values[0] == 1 {
          return true
        }
        return false
      }
      """,
      expression: "!startsWithOne([]) && startsWithOne([1]) && !startsWithOne([2])"
    )
  }

  @Test("If bindings reach later conditions and success body")
  func dependentBindings() async throws {
    try await check(
      declarations: """
      func matches(_ candidate: String?) -> Bool {
        if let first = candidate, !first.isEmpty,
          let second = [first].first, second == first {
          return second == "Model"
        }
        return false
      }
      """,
      expression: "matches(\"Model\") && !matches(nil) && !matches(\"\") && !matches(\"Other\")"
    )
  }

  @Test("Failed if conditions keep outer shadowed value in else")
  func failureScope() async throws {
    try await check(
      declarations: """
      func keepsOuterValue(_ candidate: String?) -> Bool {
        let value = 7
        if let value = candidate, value.isEmpty {
          return false
        } else {
          return value == 7
        }
      }
      """,
      expression: "keepsOuterValue(\"Model\") && keepsOuterValue(nil) && !keepsOuterValue(\"\")"
    )
  }

  @Test("Successful if conditions restore outer scope after branch")
  func successScope() async throws {
    try await check(
      declarations: """
      func keepsOuterValue(_ candidate: String?) -> Bool {
        let value = 7
        if let value = candidate, value == "Model" {
          let length = value.count
        }
        return value == 7
      }
      """,
      expression: "keepsOuterValue(\"Model\") && keepsOuterValue(nil)"
    )
  }

  @Test("Guard bindings reach later conditions and following statements")
  func guardBindings() async throws {
    try await check(
      declarations: """
      func matches(_ candidate: String?) -> Bool {
        guard let first = candidate, !first.isEmpty,
          let second = [first].first, second == first else {
          return false
        }
        return first == "Model" && second == "Model"
      }
      """,
      expression: "matches(\"Model\") && !matches(nil) && !matches(\"\") && !matches(\"Other\")"
    )
  }

  @Test("Guard conditions stop before unsafe later expressions")
  func guardShortCircuit() async throws {
    try await check(
      declarations: """
      func startsWithOne(_ values: [Int]) -> Bool {
        guard !values.isEmpty, values[0] == 1 else {
          return false
        }
        return true
      }
      """,
      expression: "!startsWithOne([]) && startsWithOne([1]) && !startsWithOne([2])"
    )
  }

  @Test("Failed guard conditions keep outer shadowed value in failure body")
  func guardFailureScope() async throws {
    try await check(
      declarations: """
      func keepsOuterValue(_ candidate: String?) -> Bool {
        let value = 7
        guard let value = candidate, value.isEmpty else {
          return value == 7
        }
        return false
      }
      """,
      expression: "keepsOuterValue(\"Model\") && keepsOuterValue(nil) && !keepsOuterValue(\"\")"
    )
  }

  @Test(
    "Condition bindings stay unavailable outside success scope",
    arguments: [
      "if let value = candidate, !value.isEmpty { return true }; return value.isEmpty",
      "if let value = candidate, !value.isEmpty { return true } else { return value.isEmpty }",
      "guard let value = candidate, !value.isEmpty else { return value.isEmpty }; return true",
    ]
  )
  func rejectedScope(body: String) async throws {
    let project = try correctionProject(
      declarations: "func inspect(_ candidate: String?) -> Bool { \(body) }",
      ruleBody: "try await app.classes.violations(of: .isFinal)"
    )
    let program = await RuleProgram.loaded(
      fromFiles: [project.fileURL(for: "ProjectRules.swift").path]
    )

    #expect(program.rules.isEmpty)
    #expect(program.errors.contains { $0.message == "'value' is not declared" })
  }

  @Test("Every condition must produce Bool", arguments: [
    "if true, 1 { return true }; return false",
    "guard true, 1 else { return false }; return true",
  ])
  func rejectedBoolean(body: String) async throws {
    let project = try correctionProject(
      declarations: "func inspect() -> Bool { \(body) }",
      ruleBody: "try await app.classes.violations(of: .isFinal)"
    )
    let program = await RuleProgram.loaded(
      fromFiles: [project.fileURL(for: "ProjectRules.swift").path]
    )

    #expect(program.rules.isEmpty)
    #expect(program.errors
      .contains { $0.message == "the condition must be Bool, not Int" })
  }

  private func check(declarations: String, expression: String) async throws {
    let project = try correctionProject(
      declarations: declarations,
      ruleBody: """
      try await app.classes.violations(of: Matcher<Class>("meet conditions") { _ in
        \(expression)
      })
      """
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.checkedCount == 1)
    #expect(findings.violations.isEmpty)
  }
}
