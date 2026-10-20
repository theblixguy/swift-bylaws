import BylawsCore
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing
@testable import BylawsInterpreter

@Suite("Portable range counts")
struct RangeCountTests {
  @Test("Range count reports overflow as rule error")
  func countOverflow() async throws {
    let project = try rulesProject(
      rules: """
      Rule("range") {
        let span = -1..<9223372036854775807
        let length = span.count
        app.classes.violations(of: .isFinal)
      }
      """,
      sources: ["Sources/Model.swift": "class Model {}"]
    )
    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)

    await #expect {
      try await rule.findings()
    } throws: { error in
      guard let ruleError = error as? RuleError,
            case let .other(cause) = ruleError.cause,
            let failure = cause as? RuntimeError else { return false }
      return failure.message == "Range.count must fit in Int. Use a smaller range."
        && failure.location.filePath == project
        .fileURL(for: "ProjectRules.swift").path
        && failure.location.line == 8
    }
  }

  @Test("Wide range retains bounds and membership")
  func wideRange() async throws {
    let project = try rulesProject(
      rules: """
      Rule("range") {
        let span = -1..<9223372036854775807
        if span.lowerBound == -1 && span.upperBound == 9223372036854775807
          && span.contains(0) {
          app.classes.violations(of: .isFinal)
        }
      }
      """,
      sources: ["Sources/Model.swift": "class Model {}"]
    )

    #expect(try await offenderNames(ofFirstRuleIn: project) == ["Model"])
  }

  @Test("Representable counts retain exact value", arguments: [
    (-5..<2, 7),
    (0..<Int.max, Int.max),
    (-Int.max..<0, Int.max),
    (-3 ..< -3, 0),
  ])
  func representableCounts(range: Range<Int>, expected: Int) async throws {
    let evaluator = RuntimeEvaluator(globals: RuntimeEnvironment())
    var state = RuntimeEvaluationState(limits: .standard)
    let result = try await evaluator.member(
      named: .count, of: .integerRange(range),
      at: .start(of: "Bylaws.swift"), state: &state
    )
    guard case let .integer(count) = result else {
      Issue.record("Range.count must return Int")
      return
    }

    #expect(count == expected)
  }
}
