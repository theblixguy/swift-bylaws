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

  func dictionaryValue(
    _ receiver: RuntimeValue,
    key: RuntimeValue,
    at location: DeclarationLocation
  ) throws(RuntimeError) -> RuntimeValue {
    if case let .optional(wrapped) = receiver {
      guard let wrapped else { return .optional(nil) }
      return try dictionaryValue(wrapped, key: key, at: location)
        .optionalChained
    }
    guard case let .dictionary(values) = receiver else {
      throw RuntimeError(
        message: "Subscript must have a Dictionary receiver",
        location: location
      )
    }
    return .optional(values[try RuntimeDictionaryKey(key, at: location)])
  }
}
