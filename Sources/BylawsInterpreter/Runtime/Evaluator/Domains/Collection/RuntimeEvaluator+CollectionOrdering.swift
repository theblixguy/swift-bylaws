import BylawsSemantics

extension RuntimeEvaluator {
  func sorted(
    _ values: [RuntimeValue],
    by comparison: RuntimeValue?,
    at location: DeclarationLocation,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> [RuntimeValue] {
    try await stableSorted(
      values,
      state: &state
    ) { lhs, rhs, state throws(RuntimeError) in
      try await compare(
        lhs,
        rhs,
        using: comparison,
        at: location,
        state: &state
      )
    }
  }

  func stableSorted<Element: Sendable>(
    _ values: [Element], state: inout RuntimeEvaluationState,
    by comparison: (
      Element,
      Element,
      inout RuntimeEvaluationState
    ) async throws(RuntimeError) -> Bool
  ) async throws(RuntimeError) -> [Element] {
    guard values.count > 1 else { return values }
    var source = values
    var destination = values
    var width = 1
    // The evaluator awaits comparisons, so Swift's synchronous sort cannot run them.
    while width < source.count {
      for start in stride(from: 0, to: source.count, by: width * 2) {
        let middle = min(start + width, source.count)
        let end = min(middle + width, source.count)
        var left = start
        var right = middle
        for output in start..<end {
          if left == middle {
            destination[output] = source[right]
            right += 1
          } else if right == end {
            destination[output] = source[left]
            left += 1
          } else if try await comparison(
            source[right], source[left], &state
          ) {
            destination[output] = source[right]
            right += 1
          } else {
            destination[output] = source[left]
            left += 1
          }
        }
      }
      swap(&source, &destination)
      width *= 2
    }
    return source
  }

  func compare(
    _ lhs: RuntimeValue,
    _ rhs: RuntimeValue,
    using callable: RuntimeValue?,
    at location: DeclarationLocation,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> Bool {
    try step(at: location, state: &state)
    let result: RuntimeValue
    switch callable {
    case nil:
      result = try applyBinary("<", left: lhs, right: rhs, at: location)
    case let .closure(closure):
      result = try await invokeSynchronous(
        closure, arguments: [lhs, rhs], kind: "comparison",
        allowsThrowing: true, state: &state
      )
    case let .function(function):
      let parameters = function.definition.parameters
      guard parameters.count == 2 else {
        throw RuntimeError(
          message: "the comparison takes two parameters", location: location
        )
      }
      result = try await invokeSynchronous(
        function,
        arguments: [lhs, rhs],
        allowsThrowing: true,
        at: location,
        state: &state
      )
    default:
      throw RuntimeError(
        message: "sorted takes a comparison closure or function",
        location: location
      )
    }
    guard case let .boolean(value) = result else {
      throw RuntimeError(
        message: "the comparison must return Bool", location: location
      )
    }
    return value
  }
}
