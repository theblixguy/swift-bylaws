import BylawsSemantics

extension RuntimeEvaluator {
  func evaluate(
    _ body: RuntimeBody,
    in environment: RuntimeEnvironment,
    builder: RuntimeBuilder? = nil,
    reportedAt location: DeclarationLocation? = nil,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    let builder = body.containsReturn ? nil : builder
    let result = try await evaluateBody(
      body,
      in: environment,
      collecting: builder != nil,
      state: &state
    ).value
    if let builder, case let .array(values) = result {
      return try builder.combine(
        values,
        at: location ?? body.statements.first?
          .location ?? .start(of: "<interpreted rule>")
      )
    }
    return result
  }

  private func evaluateBody(
    _ body: RuntimeBody,
    in environment: RuntimeEnvironment,
    collecting: Bool = false,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeBodyResult {
    var environment = environment
    var last: RuntimeValue = .void
    var collected: [RuntimeValue] = []
    for statement in body.statements {
      try step(at: statement.location, state: &state)
      switch statement.kind {
      case let .binding(name, type, expression):
        let value = try await evaluate(
          expression,
          in: environment,
          state: &state
        )
        let boundValue: RuntimeValue
        if let type {
          guard let coerced = value.coerced(to: type) else {
            throw RuntimeError(
              message: "'\(name)' must be \(type.writtenName)",
              location: statement.location
            )
          }
          boundValue = coerced
        } else {
          boundValue = value
        }
        environment.bind(boundValue, to: name)
        last = .void
      case let .expression(expression):
        last = try await evaluate(
          expression,
          in: environment,
          state: &state
        )
        if collecting { collected.append(last) }
      case let .forStatement(name, sequence, body):
        let sequence = try await evaluate(
          sequence,
          in: environment,
          state: &state
        )
        guard let values = sequence.sequenceElements else {
          throw RuntimeError(
            message: "for takes a sequence",
            location: statement.location
          )
        }
        for value in values {
          try step(at: statement.location, state: &state)
          var iteration = environment
          iteration.bind(value, to: name)
          let result = try await evaluateBody(
            body,
            in: iteration,
            collecting: collecting,
            state: &state
          )
          if result.returned { return result }
          if collecting,
             case let .array(values) = result
             .value { collected.append(contentsOf: values) }
        }
        last = .void
      case let .guardStatement(condition, failure):
        switch try await evaluate(condition, in: environment, state: &state) {
        case let .satisfied(binding):
          if let binding {
            environment.bind(binding.value, to: binding.name)
          }
        case .notSatisfied:
          let result = try await evaluateBody(
            failure,
            in: environment,
            state: &state
          )
          if result.returned { return result }
          throw RuntimeError(
            message: "a guard failure must leave the current scope",
            location: statement.location
          )
        }
      case let .ifStatement(condition, success, failure):
        let evaluated = try await evaluate(
          condition,
          in: environment,
          state: &state
        )
        let selected: RuntimeBody?
        var branchEnvironment = environment
        switch evaluated {
        case let .satisfied(binding):
          selected = success
          if let binding {
            branchEnvironment.bind(binding.value, to: binding.name)
          }
        case .notSatisfied:
          selected = failure
        }
        if let selected {
          let result = try await evaluateBody(
            selected,
            in: branchEnvironment,
            collecting: collecting,
            state: &state
          )
          if result.returned { return result }
          last = result.value
          if collecting,
             case let .array(values) = result
             .value { collected.append(contentsOf: values) }
        } else {
          last = .void
        }
      case let .return(expression):
        let value =
          if let expression {
            try await evaluate(
              expression,
              in: environment,
              state: &state
            )
          } else {
            RuntimeValue.void
          }
        return RuntimeBodyResult(value: value, returned: true)
      }
    }
    return RuntimeBodyResult(
      value: collecting ? .array(collected) : last,
      returned: false
    )
  }

  private func evaluate(
    _ condition: RuntimeCondition,
    in environment: RuntimeEnvironment,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeConditionResult {
    switch condition {
    case let .boolean(expression):
      guard case let .boolean(value) = try await evaluate(
        expression,
        in: environment,
        state: &state
      )
      else {
        throw RuntimeError(
          message: "a condition must be Bool",
          location: expression.location
        )
      }
      return value ? .satisfied(binding: nil) : .notSatisfied
    case let .optionalBinding(name, expression):
      let value = try await evaluate(
        expression,
        in: environment,
        state: &state
      )
      guard case let .optional(wrapped) = value else {
        throw RuntimeError(
          message: "an optional binding takes an Optional value",
          location: expression.location
        )
      }
      guard let wrapped else { return .notSatisfied }
      return .satisfied(
        binding: RuntimeConditionBinding(name: name, value: wrapped)
      )
    }
  }
}

private struct RuntimeBodyResult {
  let value: RuntimeValue
  let returned: Bool
}

private struct RuntimeConditionBinding {
  let name: String
  let value: RuntimeValue
}

private enum RuntimeConditionResult {
  case notSatisfied
  case satisfied(binding: RuntimeConditionBinding?)
}
