import BylawsSemantics

extension RuntimeEvaluator {
  func groupDictionary(
    arguments: RuntimeArguments,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    let values = try arguments.sequence(at: 0)
    let transform = try arguments.value(at: 1)
    var groups: [RuntimeDictionaryKey: [RuntimeValue]] = [:]
    for value in values {
      try step(at: arguments.location, state: &state)
      let key = try await self.transform(transform, value: value, state: &state)
      groups[try RuntimeDictionaryKey(key, at: arguments.location), default: []]
        .append(value)
    }
    return .dictionary(groups.mapValues(RuntimeValue.array))
  }

  func mapDictionary(
    _ values: [RuntimeDictionaryKey: RuntimeValue],
    arguments: RuntimeArguments,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    let transform = try arguments.value(at: 0)
    var result: [RuntimeDictionaryKey: RuntimeValue] = [:]
    result.reserveCapacity(values.count)
    for (key, value) in values {
      try step(at: arguments.location, state: &state)
      result[key] = try await self.transform(
        transform,
        value: value,
        state: &state
      )
    }
    return .dictionary(result)
  }
}
