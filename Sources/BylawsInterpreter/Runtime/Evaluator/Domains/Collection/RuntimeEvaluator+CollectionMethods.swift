import BylawsSemantics

extension RuntimeEvaluator {
  func collectionMethod(
    _ name: SupportedAPI.Method,
    values: ArraySlice<RuntimeValue>,
    preservesSet: Bool,
    arguments: RuntimeArguments,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    switch name {
    case .dropFirst:
      guard arguments.hasLabels([]) || arguments.hasLabels([nil]) else {
        throw RuntimeError(
          message: "dropFirst takes an optional count",
          location: arguments.location
        )
      }
      let count = arguments.values.isEmpty ? 1 : try arguments.integer(at: 0)
      guard count >= 0 else {
        throw RuntimeError(
          message: "dropFirst must use a nonnegative count",
          location: arguments.location
        )
      }
      return .arraySlice(values.dropFirst(count))
    case .prefix:
      guard arguments.hasLabels([.while]) || arguments.hasLabels([nil]) else {
        throw RuntimeError(
          message: "prefix takes a count or predicate",
          location: arguments.location
        )
      }
      let predicate = try arguments.value(at: 0)
      if arguments.hasLabels([nil]), case let .integer(count) = predicate {
        guard count >= 0 else {
          throw RuntimeError(
            message: "prefix must use a nonnegative count",
            location: arguments.location
          )
        }
        return .arraySlice(values.prefix(count))
      }
      var count = 0
      for value in values {
        try step(at: arguments.location, state: &state)
        guard try await self.predicate(predicate, value: value, state: &state)
        else { break }
        count += 1
      }
      return .arraySlice(values.prefix(count))
    case .sorted:
      guard arguments.hasLabels([]) || arguments.hasLabels([.by])
        || arguments.hasLabels([nil])
      else {
        throw RuntimeError(
          message: "sorted takes a comparison closure or function",
          location: arguments.location
        )
      }
      return .array(try await sorted(
        Array(values), by: arguments.values.first?.value,
        at: arguments.location,
        state: &state
      ))
    case .reversed:
      try arguments.requireLabels([], for: name)
      return .array(Array(values.reversed()))
    case .only:
      try arguments.requireLabels([], for: name)
      guard values.count == 1, let value = values.first else {
        throw RuntimeError(
          wrapping: SourceError.matchCount(values.count),
          at: arguments.location
        )
      }
      guard case .sourceSlice = value else {
        if case let .model(model) = value,
           SupportedAPI.sourceProvidingModels.contains(model.modelType)
        {
          return value
        }
        throw RuntimeError(
          message: "only takes captured source values",
          location: arguments.location
        )
      }
      return value
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
        try step(at: arguments.location, state: &state)
        let transformed = try await transform(
          try arguments.value(at: 0),
          value: value,
          state: &state
        )
        guard let elements = transformed.sequenceValues else {
          throw RuntimeError(
            message: "'flatMap' closure must return a sequence",
            location: arguments.location
          )
        }
        for element in elements {
          try step(at: arguments.location, state: &state)
          result.append(element)
        }
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
      for value in values {
        var found = false
        for candidate in other {
          try step(at: arguments.location, state: &state)
          if equals(value, candidate) {
            found = true
            break
          }
        }
        if !found { return .boolean(false) }
      }
      return .boolean(true)
    default:
      throw RuntimeError(
        message: "'\(name.rawValue)' is not a supported collection method",
        location: arguments.location
      )
    }
  }
}
