import BylawsSemantics

extension RuntimeEvaluator {
  func resolveLayoutPlan(
    _ plan: [RuntimeLayoutOperation], elements: [RuntimeValue],
    at location: DeclarationLocation, state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> [SourceListLayoutOperation] {
    var operations: [SourceListLayoutOperation] = []
    var claimed = [Bool](repeating: false, count: elements.count)
    var comparisons: [Int: RuntimeValue] = [:]
    for operation in plan {
      switch operation {
      case .layout:
        throw RuntimeError(
          wrapping: SourceListLayoutError.mixedContent,
          at: location
        )
      case let .group(group):
        var indices: [Int] = []
        for index in elements.indices where !claimed[index] {
          if try await matchesLayoutGroup(
            group,
            value: elements[index],
            state: &state
          ) {
            indices.append(index)
            claimed[index] = true
          }
        }
        if let comparison = group.comparison {
          comparisons[operations.count] = comparison
        }
        operations.append(.group(indices: indices))
      case let .separator(whitespace):
        operations.append(.separator(whitespace))
      case let .conditionalSeparator(_, whitespace):
        operations.append(.conditionalSeparator(
          gaps: [],
          whitespace: whitespace
        ))
      }
    }
    let regions = SourceListLayoutReplacement.regions(membership: claimed)
    var regionEnds = [Int](repeating: 0, count: elements.count)
    for region in regions {
      for index in region { regionEnds[index] = region.upperBound }
    }
    for index in operations.indices {
      guard let comparison = comparisons[index],
            case let .group(indices) = operations[index] else { continue }
      var ordered: [Int] = []
      var offset = 0
      while offset < indices.count {
        let start = offset
        let end = regionEnds[indices[start]]
        while offset < indices.count, indices[offset] < end { offset += 1 }
        ordered.append(contentsOf: try await sortedLayoutIndices(
          Array(indices[start..<offset]), elements: elements,
          comparison: comparison, at: location, state: &state
        ))
      }
      operations[index] = .group(indices: ordered)
    }
    var regionIDs = [Int](repeating: -1, count: elements.count)
    for (regionID, region) in regions.enumerated() {
      for index in region { regionIDs[index] = regionID }
    }
    let order = SourceListLayoutReplacement.orderedIndices(
      operations: operations, regions: regions, regionIDs: regionIDs
    )
    for (operationIndex, operation) in plan.enumerated() {
      guard case let .conditionalSeparator(condition, whitespace) = operation
      else { continue }
      var gaps = Set<Int>()
      for index in order.indices.dropFirst() {
        if try await layoutCondition(
          condition, previous: elements[order[index - 1]],
          next: elements[order[index]],
          state: &state
        ) { gaps.insert(index) }
      }
      operations[operationIndex] = .conditionalSeparator(
        gaps: gaps,
        whitespace: whitespace
      )
    }
    return operations
  }

  private func matchesLayoutGroup(
    _ group: RuntimeLayoutGroup, value: RuntimeValue,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> Bool {
    let subject: RuntimeValue
    if let projection = group.projection {
      let projected = try await transform(
        projection,
        value: value,
        state: &state
      )
      guard case let .optional(wrapped) = projected,
            let wrapped else { return false }
      subject = wrapped
    } else { subject = value }
    if case let .matcher(matcher) = group.predicate,
       case let .model(model) = subject
    {
      return try await matches(matcher, value: model, state: &state)
    }
    return try await predicate(
      group.predicate,
      value: subject,
      allowsThrowing: true,
      state: &state
    )
  }

  private func layoutCondition(
    _ condition: RuntimeLayoutOperation.Condition,
    previous: RuntimeValue, next: RuntimeValue,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> Bool {
    switch condition {
    case let .before(callable):
      return try await predicate(
        callable,
        value: next,
        allowsThrowing: true,
        state: &state
      )
    case let .after(callable):
      return try await predicate(
        callable,
        value: previous,
        allowsThrowing: true,
        state: &state
      )
    case let .between(first, second):
      if try await predicate(
        first,
        value: previous,
        allowsThrowing: true,
        state: &state
      ) {
        if try await predicate(
          second,
          value: next,
          allowsThrowing: true,
          state: &state
        ) {
          return true
        }
      }
      if try await predicate(
        first,
        value: next,
        allowsThrowing: true,
        state: &state
      ) {
        return try await predicate(
          second,
          value: previous,
          allowsThrowing: true,
          state: &state
        )
      }
      return false
    }
  }

  private func sortedLayoutIndices(
    _ indices: [Int], elements: [RuntimeValue], comparison: RuntimeValue,
    at location: DeclarationLocation, state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> [Int] {
    try await stableSorted(
      indices,
      state: &state
    ) { lhs, rhs, state throws(RuntimeError) in
      try await compare(
        elements[lhs], elements[rhs], using: comparison, at: location,
        state: &state
      )
    }
  }
}
