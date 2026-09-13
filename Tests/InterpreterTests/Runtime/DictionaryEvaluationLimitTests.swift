import BylawsSemantics
import Testing
@testable import BylawsInterpreter

@Suite("Dictionary evaluation limits")
struct DictionaryEvaluationLimitTests {
  @Test("Grouping checks instruction budget before each key path")
  func groupingBudget() async throws {
    let location = DeclarationLocation.start(of: "Bylaws.swift")
    let evaluator = RuntimeEvaluator(globals: RuntimeEnvironment())
    var state = RuntimeEvaluationState(limits: .init(
      maximumInstructions: 0,
      maximumCallDepth: 10
    ))
    let arguments = RuntimeArguments(values: [
      ("grouping", .array([.string("one")])),
      ("by", .keyPath([.count], location)),
    ], location: location)

    await #expect {
      try await evaluator.groupDictionary(arguments: arguments, state: &state)
    } throws: { error in
      (error as? RuntimeError)?.message == "the rule exceeded its evaluation budget"
    }
  }

  @Test("Mapping checks instruction budget before each key path")
  func mappingBudget() async throws {
    let location = DeclarationLocation.start(of: "Bylaws.swift")
    let evaluator = RuntimeEvaluator(globals: RuntimeEnvironment())
    var state = RuntimeEvaluationState(limits: .init(
      maximumInstructions: 0,
      maximumCallDepth: 10
    ))
    let arguments = RuntimeArguments(values: [
      (nil, .keyPath([.count], location)),
    ], location: location)

    await #expect {
      try await evaluator.mapDictionary(
        [.string("one"): .array([.integer(1)])], arguments: arguments,
        state: &state
      )
    } throws: { error in
      (error as? RuntimeError)?.message == "the rule exceeded its evaluation budget"
    }
  }
}
