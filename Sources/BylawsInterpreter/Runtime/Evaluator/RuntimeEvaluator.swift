import BylawsCore
import BylawsSemantics

struct RuntimeEvaluator: Sendable {
  let globals: RuntimeEnvironment
  let indexProvider: (any RuntimeIndexProvider)?

  init(
    globals: RuntimeEnvironment,
    indexProvider: (any RuntimeIndexProvider)? = nil
  ) {
    self.globals = globals
    self.indexProvider = indexProvider
  }

  func evaluate(
    _ expression: RuntimeExpression,
    in environment: RuntimeEnvironment,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    try step(at: expression.location, state: &state)
    switch expression.kind {
    case let .subscriptCall(base, key):
      let receiver = try await evaluate(base, in: environment, state: &state)
      if case .optional(nil) = receiver { return .optional(nil) }
      let keyValue = try await evaluate(key, in: environment, state: &state)
      return try dictionaryValue(
        receiver,
        key: keyValue,
        at: expression.location
      )
    case let .constructor(constructor):
      return .genericType(name: constructor.rawValue, arguments: [])
    case .implicitConstructor:
      throw RuntimeError(
        message: "Initialiser must have a contextual type. Write the type name before its arguments.",
        location: expression.location
      )
    case let .array(elements):
      var values: [RuntimeValue] = []
      for element in elements {
        values.append(
          try await evaluate(element, in: environment, state: &state)
        )
      }
      return .array(values)
    case let .boolean(value):
      return .boolean(value)
    case let .call(callee, arguments, trailingClosure):
      let callable = try await evaluateCallable(
        callee,
        in: environment,
        state: &state
      )
      var values: [(String?, RuntimeValue)] = []
      for argument in arguments {
        values.append(
          (
            argument.label,
            try await evaluate(
              argument.value,
              in: environment,
              state: &state
            )
          )
        )
      }
      let closure = trailingClosure.map {
        RuntimeClosure(definition: $0, captures: environment)
      }
      return try await invoke(
        callable,
        arguments: values,
        trailingClosure: closure,
        at: expression.location,
        state: &state
      )
    case let .closure(definition):
      return .closure(
        RuntimeClosure(definition: definition, captures: environment)
      )
    case let .double(value):
      return .double(value)
    case let .generic(base, arguments):
      let name: String
      switch base.kind {
      case let .reference(value): name = value
      default:
        guard case let .genericType(value, _) = try await evaluate(
          base,
          in: environment,
          state: &state
        )
        else {
          throw failure("this value cannot take generic arguments", expression)
        }
        name = value
      }
      return .genericType(name: name, arguments: arguments)
    case let .integer(value):
      return .integer(value)
    case let .interpolatedString(segments):
      var result = ""
      for segment in segments {
        switch segment {
        case let .text(text): result += text
        case let .expression(value):
          let evaluated = try await evaluate(
            value,
            in: environment,
            state: &state
          )
          result += try string(from: evaluated, at: value.location)
        }
      }
      return .string(result)
    case let .keyPath(components):
      return .keyPath(components, expression.location)
    case let .member(base, name):
      let receiver = try await evaluate(
        base,
        in: environment,
        state: &state
      )
      return try await member(
        named: name,
        of: receiver,
        at: expression.location,
        state: &state
      )
    case .nilLiteral:
      return .optional(nil)
    case let .prefix(operatorName, operand):
      let value = try await evaluate(
        operand,
        in: environment,
        state: &state
      )
      return try prefix(
        operatorName,
        value: value,
        at: expression.location
      )
    case let .binary(left, operatorName, right):
      return try await binary(
        left: left,
        operator: operatorName,
        right: right,
        environment: environment,
        state: &state
      )
    case let .reference(name):
      if let value = environment[name] {
        return value.capturingFunctions(in: environment)
      }
      if let value = globals[name] {
        return value.capturingFunctions(in: globals)
      }
      if SupportedAPI.runtimeTypeNames.contains(name) {
        return .genericType(name: name, arguments: [])
      }
      throw RuntimeError.undeclaredName(name, at: expression.location)
    case let .staticMember(literal):
      return .member(literal)
    case let .string(value):
      return .string(value)
    }
  }

  func invoke(
    _ closure: RuntimeClosure,
    arguments: [RuntimeValue],
    builder: RuntimeBuilder? = nil,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    try enterCall(at: closure.definition.location, state: &state)
    defer { state.callDepth -= 1 }
    var environment = closure.captures
    let parameters = closure.definition.parameters
    if parameters.isEmpty {
      for (index, value) in arguments.enumerated() {
        environment.bind(value, to: "$\(index)")
      }
    } else {
      guard parameters.count == arguments.count else {
        throw RuntimeError(
          message: "the closure takes \(argumentCountDescription(parameters.count))",
          location: closure.definition.location
        )
      }
      for (name, value) in zip(parameters, arguments) {
        environment.bind(value, to: name)
      }
    }
    return try await evaluate(
      closure.definition.body,
      in: environment,
      builder: builder,
      reportedAt: closure.definition.location,
      state: &state
    )
  }

  func step(
    at location: DeclarationLocation,
    state: inout RuntimeEvaluationState
  ) throws(RuntimeError) {
    guard !Task.isCancelled else {
      throw RuntimeError(
        message: "the run was cancelled",
        location: location,
        kind: .cancelled
      )
    }
    state.remainingInstructions -= 1
    guard state.remainingInstructions >= 0 else {
      throw RuntimeError(
        message: "the rule exceeded its evaluation budget",
        location: location
      )
    }
  }

  func enterCall(
    at location: DeclarationLocation,
    state: inout RuntimeEvaluationState
  ) throws(RuntimeError) {
    state.callDepth += 1
    guard state.callDepth <= state.maximumCallDepth else {
      state.callDepth -= 1
      throw RuntimeError(
        message: "the rule exceeded its call-depth limit",
        location: location
      )
    }
  }

  private func failure(
    _ message: String,
    _ expression: RuntimeExpression
  ) -> RuntimeError {
    RuntimeError(message: message, location: expression.location)
  }
}
