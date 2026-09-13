extension RuntimeEvaluator {
  func collectionMethod(
    _ name: SupportedAPI.Method,
    values: [RuntimeValue],
    preservesSet: Bool,
    arguments: RuntimeArguments,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    switch name {
    case .filter:
      try arguments.requireLabels([nil], for: name)
      var result: [RuntimeValue] = []
      for value in values
        where try await predicate(
          try arguments.value(at: 0),
          value: value,
          state: &state
        )
      {
        result.append(value)
      }
      return preservesSet ? .set(result) : .array(result)
    case .map:
      try arguments.requireLabels([nil], for: name)
      var result: [RuntimeValue] = []
      for value in values {
        result.append(
          try await transform(
            try arguments.value(at: 0),
            value: value,
            state: &state
          )
        )
      }
      return .array(result)
    case .compactMap:
      try arguments.requireLabels([nil], for: name)
      var result: [RuntimeValue] = []
      for value in values {
        let transformed = try await transform(
          try arguments.value(at: 0),
          value: value,
          state: &state
        )
        switch transformed {
        case let .optional(value?): result.append(value)
        case .optional(nil), .void: break
        default: result.append(transformed)
        }
      }
      return .array(result)
    case .flatMap:
      try arguments.requireLabels([nil], for: name)
      var result: [RuntimeValue] = []
      for value in values {
        let transformed = try await transform(
          try arguments.value(at: 0),
          value: value,
          state: &state
        )
        guard case let .array(elements) = transformed else {
          throw RuntimeError(
            message: "'flatMap' closure must return an array",
            location: arguments.location
          )
        }
        result.append(contentsOf: elements)
      }
      return .array(result)
    case .contains:
      let argument = try arguments.value(at: 0)
      let isPredicate =
        switch argument {
        case .closure, .keyPath, .function: true
        default: false
        }
      guard arguments.hasLabels([nil])
        || isPredicate && arguments.hasLabels([.where])
      else {
        throw RuntimeError(
          message: "'contains' takes one value or a 'where:' predicate",
          location: arguments.location
        )
      }
      if isPredicate {
        for value in values
          where try await predicate(
            argument,
            value: value,
            state: &state
          )
        {
          return .boolean(true)
        }
        return .boolean(false)
      }
      return .boolean(values.contains { equals($0, argument) })
    case .allSatisfy:
      try arguments.requireLabels([nil], for: name)
      for value in values
        where try await !predicate(
          try arguments.value(at: 0),
          value: value,
          state: &state
        )
      {
        return .boolean(false)
      }
      return .boolean(true)
    case .isSubset:
      try arguments.requireLabels([.of], for: name)
      let other = try arguments.sequence(at: 0)
      return .boolean(
        values.allSatisfy { value in
          other.contains { equals(value, $0) }
        }
      )
    default:
      throw RuntimeError(
        message: "'\(name.rawValue)' is not a supported collection method",
        location: arguments.location
      )
    }
  }
}
