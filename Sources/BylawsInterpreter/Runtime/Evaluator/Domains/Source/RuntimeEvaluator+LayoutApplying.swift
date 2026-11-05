import BylawsSemantics

extension RuntimeEvaluator {
  func layoutApplying(
    _ parent: SourceCorrection, arguments: RuntimeArguments,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    if arguments.hasLabels([.toEach, nil]) {
      return try await applyingToEach(
        parent,
        arguments: arguments,
        state: &state
      )
    }
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

  private func applyingToEach(
    _ parent: SourceCorrection, arguments: RuntimeArguments,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    let collections = try arguments.sequence(at: 0)
    let callable = try arguments.value(at: 1)
    var corrections: [SourceCorrection] = []
    for collection in collections {
      try step(at: arguments.location, state: &state)
      let content = try await layoutResult(
        callable, at: arguments.location, inputs: [collection], state: &state
      )
      let child = try await constructLayoutOperation(
        RuntimeArguments(
          values: [(nil, collection), ("layout", content)],
          location: arguments.location
        ), state: &state
      )
      corrections.append(try child.correction(at: arguments.location))
    }
    do {
      return .layoutCorrection(try parent.applyingLayoutCorrections(
        SourceCorrection(combining: corrections)
      ))
    } catch { throw RuntimeError(wrapping: error, at: arguments.location) }
  }
}
