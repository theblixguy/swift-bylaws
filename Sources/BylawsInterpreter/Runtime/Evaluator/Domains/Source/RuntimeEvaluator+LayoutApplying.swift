import BylawsSemantics

extension RuntimeEvaluator {
  func layoutApplying(
    _ parent: SourceCorrection, arguments: RuntimeArguments,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    let content = try arguments.value(at: 0)
    let result: RuntimeValue = switch content {
    case let .closure(closure):
      try await invokeSynchronous(
        closure,
        arguments: [],
        kind: "correction",
        allowsThrowing: true,
        builder: .correction,
        state: &state
      )
    case let .function(function):
      try await invokeSynchronous(
        function,
        arguments: [],
        allowsThrowing: true,
        at: arguments.location,
        state: &state
      )
    default: content
    }
    do {
      return .layoutCorrection(try parent
        .applyingLayoutCorrections(result.correction(at: arguments.location)))
    } catch { throw RuntimeError(wrapping: error, at: arguments.location) }
  }
}
