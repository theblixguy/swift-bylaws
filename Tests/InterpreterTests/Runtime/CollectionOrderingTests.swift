import BylawsCore
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing
@testable import BylawsInterpreter

@Suite("Portable collection ordering")
struct CollectionOrderingTests {
  @Test(
    "Comparisons support ascending, descending and custom orders",
    arguments: [
      OrderingCase(
        testDescription: "Ascending",
        expression: "values.sorted { $0.name < $1.name }",
        expected: ["Alpha", "Beta", "Gamma"]
      ),
      OrderingCase(
        testDescription: "Descending",
        expression: "values.sorted(by: { lhs, rhs in lhs.name > rhs.name })",
        expected: ["Gamma", "Beta", "Alpha"]
      ),
      OrderingCase(
        testDescription: "Final declarations first",
        expression: """
        values.sorted { lhs, rhs in
          if lhs.isFinal != rhs.isFinal { return lhs.isFinal }
          return lhs.name < rhs.name
        }
        """,
        expected: ["Beta", "Alpha", "Gamma"]
      ),
      OrderingCase(
        testDescription: "Equal keys retain source order",
        expression: "values.sorted { lhs, rhs in lhs.isFinal && !rhs.isFinal }",
        expected: ["Beta", "Gamma", "Alpha"]
      ),
      OrderingCase(
        testDescription: "Reversed selection",
        expression: "values.reversed()",
        expected: ["Beta", "Alpha", "Gamma"]
      ),
      OrderingCase(
        testDescription: "Reversed sorted array",
        expression: "values.sorted { $0.name < $1.name }.reversed()",
        expected: ["Gamma", "Beta", "Alpha"]
      ),
    ]
  )
  func modelOrder(_ testCase: OrderingCase) async throws {
    let project = try rulesProject(
      rules: """
      Rule("order") {
        let values = try await app.classes
        let ordered = \(testCase.expression)
        return Violations(rule: "test order", offenders: ordered, checkedCount: values.count)
      }
      """,
      sources: [
        "Sources/Models.swift": "class Gamma {}\nclass Alpha {}\nfinal class Beta {}",
      ]
    )

    let actual = try await offenderNames(ofFirstRuleIn: project)

    #expect(actual == testCase.expected)
  }

  @Test("Throwing comparison helper reads source projections")
  func throwingHelper() async throws {
    let project = try correctionProject(
      declarations: """
      func comesFirst(_ lhs: Class, _ rhs: Class) throws -> Bool {
        try lhs.nameSource.text < rhs.nameSource.text
      }
      """,
      ruleBody: """
      let values = try await app.classes
      let ordered = try values.sorted(by: comesFirst)
      Violations(rule: "test order", offenders: ordered, checkedCount: values.count)
      """
    )
    try project.write(
      "class Gamma {}\nclass Alpha {}",
      to: "Sources/Model.swift"
    )

    let actual = try await offenderNames(ofFirstRuleIn: project)

    #expect(actual == ["Alpha", "Gamma"])
  }

  @Test("Throwing comparison closure preserves projection failures")
  func throwingProjection() async throws {
    let project = try correctionProject(ruleBody: """
    let values = try await app.classes
    let ordered = try values.sorted { lhs, rhs in
      try lhs.nameSource.slice(999..<1000).text < rhs.nameSource.text
    }
    Violations(rule: "test order", offenders: ordered, checkedCount: values.count)
    """)
    try project.write(
      "class Alpha {}\nclass Beta {}",
      to: "Sources/Model.swift"
    )
    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)

    await #expect(throws: RuleError.self) {
      try await rule.violations()
    }
  }

  @Test(
    "Ordered values support arrays, sets and empty collections",
    arguments: [
      "[3, 1, 2].sorted { $0 < $1 } == [1, 2, 3]",
      "[3, 1, 2].sorted() == [1, 2, 3]",
      "[3.5, 1.5, 2.5].sorted() == [1.5, 2.5, 3.5]",
      "[\"Gamma\", \"Alpha\", \"Beta\"].sorted() == [\"Alpha\", \"Beta\", \"Gamma\"]",
      "Set([3, 1, 2]).sorted { $0 > $1 } == [3, 2, 1]",
      "[1].sorted { $0 < $1 } == [1]",
      "[1].filter { $0 > 1 }.sorted { $0 < $1 }.isEmpty",
      "[1].filter { $0 > 1 }.reversed().isEmpty",
    ]
  )
  func valueOrder(expression: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("order") {
        let values = try await app.classes
        values.violations(of: Matcher<Class>("preserve value order") { _ in
          \(expression)
        })
      }
      """,
      sources: ["Sources/Model.swift": "class Model {}"]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.isEmpty)
  }

  @Test("Stored throwing comparison retains parameter types and effects")
  func storedComparison() async throws {
    let project = try correctionProject(
      declarations: """
      let comesFirst = { (lhs: Class, rhs: Class) -> Bool in
        try lhs.nameSource.text < rhs.nameSource.text
      }
      """,
      ruleBody: """
      let values = try await app.classes
      let ordered = try values.sorted(by: comesFirst)
      Violations(rule: "test order", offenders: ordered, checkedCount: values.count)
      """
    )
    try project.write(
      "class Gamma {}\nclass Alpha {}",
      to: "Sources/Model.swift"
    )

    let actual = try await offenderNames(ofFirstRuleIn: project)

    #expect(actual == ["Alpha", "Gamma"])
  }

  @Test("Default ordering observes evaluation budget")
  func instructionBudget() async throws {
    let evaluator = RuntimeEvaluator(globals: RuntimeEnvironment())
    let location = DeclarationLocation.start(of: "ProjectRules.swift")
    var state = RuntimeEvaluationState(limits: RuntimeLimits(
      maximumInstructions: 0, maximumCallDepth: 1
    ))

    await #expect {
      try await evaluator.sorted(
        [.integer(2), .integer(1)], by: nil, at: location, state: &state
      )
    } throws: { error in
      guard let error = error as? RuntimeError else { return false }
      return error.message == "the rule exceeded its evaluation budget"
    }
  }

  @Test("Default ordering observes cancellation")
  func cancellation() async {
    let evaluator = RuntimeEvaluator(globals: RuntimeEnvironment())
    let location = DeclarationLocation.start(of: "ProjectRules.swift")
    let result = await withTaskGroup(of: Bool.self) { group in
      group.cancelAll()
      group.addTask {
        var state = RuntimeEvaluationState(limits: .standard)
        do {
          _ = try await evaluator.sorted(
            [.integer(2), .integer(1)], by: nil, at: location, state: &state
          )
          return false
        } catch {
          return (error as? RuntimeError)?.kind == .cancelled
        }
      }
      return await group.next()
    }

    #expect(result == true)
  }

  @Test(
    "Comparison rejects wrong arity, result type and suspension",
    arguments: [
      RejectionCase(
        expression: "values.sorted()",
        message: "Use sorted(by:)"
      ),
      RejectionCase(
        expression: "values.sorted { value in value.isFinal }",
        message: "the closure takes 1 argument, not 2"
      ),
      RejectionCase(
        expression: "values.sorted { lhs, rhs in lhs.name }",
        message: "must be Bool"
      ),
      RejectionCase(
        expression: """
        values.sorted { lhs, rhs in
          let classes = try await app.classes
          return classes.isEmpty
        }
        """,
        message: "a synchronous closure cannot suspend"
      ),
    ]
  )
  func rejectedComparison(_ testCase: RejectionCase) async throws {
    let project = try correctionProject(ruleBody: """
    let values = try await app.classes
    let ordered = \(testCase.expression)
    try await app.classes.violations(of: .isFinal)
    """)
    let program = await RuleProgram.loaded(
      fromFiles: [project.fileURL(for: "ProjectRules.swift").path]
    )

    #expect(
      program.errors.contains { $0.message.contains(testCase.message) },
      "\(program.errors.map(\.message))"
    )
    #expect(program.rules.isEmpty)
  }
}

struct OrderingCase: Sendable, Codable, CustomTestStringConvertible {
  let testDescription: String
  let expression: String
  let expected: [String]
}

struct RejectionCase: Sendable, Codable, CustomTestStringConvertible {
  let expression: String
  let message: String

  var testDescription: String { expression }
}
