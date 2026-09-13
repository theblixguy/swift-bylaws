import BylawsCore
import BylawsSemantics

extension RuntimeEvaluator {
  func invoke(
    _ callable: RuntimeValue,
    arguments values: [(String?, RuntimeValue)],
    trailingClosure: RuntimeClosure?,
    at location: DeclarationLocation,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    var values = values
    if let trailingClosure {
      values.append((nil, .closure(trailingClosure)))
    }
    let arguments = RuntimeArguments(values: values, location: location)
    switch callable {
    case let .closure(closure):
      guard values.allSatisfy({ $0.0 == nil }) else {
        throw RuntimeError(
          message: "closure arguments do not have labels",
          location: location
        )
      }
      return try await invoke(
        closure,
        arguments: values.map(\.1),
        state: &state
      )
    case let .function(function):
      return try await invoke(
        function,
        arguments: arguments,
        state: &state
      )
    case let .boundMethod(receiver, name):
      return try await invoke(
        method: name,
        of: receiver,
        arguments: arguments,
        state: &state
      )
    case let .genericType(name, typeArguments):
      return try await construct(
        type: name,
        typeArguments: typeArguments,
        arguments: arguments,
        state: &state
      )
    case let .member(name):
      return try prebuiltMatcher(
        named: name.rawValue,
        arguments: arguments
      )
    case let .optional(callable):
      guard let callable else { return .optional(nil) }
      return try await invoke(
        callable,
        arguments: values,
        trailingClosure: nil,
        at: location,
        state: &state
      ).optionalChained
    default:
      throw RuntimeError(
        message: "this value is not callable",
        location: location
      )
    }
  }

  private func invoke(
    _ function: RuntimeFunction,
    arguments: RuntimeArguments,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    let definition = function.definition
    if state.synchronousClosureDepth > 0,
       definition.isAsync || definition.isThrowing
    {
      throw RuntimeError(
        message: "a synchronous closure cannot call an async or throwing helper",
        location: arguments.location
      )
    }
    try enterCall(at: definition.location, state: &state)
    defer { state.callDepth -= 1 }
    guard definition.parameters.count == arguments.values.count else {
      throw RuntimeError(
        message: "'\(definition.name)' takes \(argumentCountDescription(definition.parameters.count))",
        location: arguments.location
      )
    }
    let expectedLabels = definition.parameters.map(\.externalName)
    try arguments.requireLabels(expectedLabels, for: definition.name)
    var environment = function.captures ?? globals
    for (parameter, argument) in zip(
      definition.parameters,
      arguments.values
    ) {
      guard let value = argument.value.coerced(to: parameter.type) else {
        throw RuntimeError(
          message: "'\(parameter.localName)' must be \(parameter.type.writtenName)",
          location: arguments.location
        )
      }
      environment.bind(value, to: parameter.localName)
    }
    let result = try await evaluate(
      definition.body,
      in: environment,
      state: &state
    )
    guard let result = result.coerced(to: definition.returnType) else {
      throw RuntimeError(
        message: "'\(definition.name)' must return \(definition.returnType.writtenName)",
        location: definition.location
      )
    }
    return result
  }

  func prebuiltMatcher(
    named name: String,
    arguments: RuntimeArguments
  ) throws(RuntimeError) -> RuntimeValue {
    let literalArguments = try arguments.values
      .map { argument throws(RuntimeError) in
        ParsedCall.Argument(
          rawLabel: argument.label,
          value: try literal(from: argument.value, at: arguments.location)
        )
      }
    let call = ParsedCall(
      name: name,
      arguments: literalArguments,
      location: arguments.location
    )
    guard let matcher = SupportedAPI.matcher(named: name) else {
      throw RuntimeError(
        message: "'\(name)' is not a supported static member",
        location: arguments.location
      )
    }
    guard call.accepts(matcher.arguments) else {
      throw RuntimeError(
        message: "'\(name)' \(matcher.arguments.requirement)",
        location: arguments.location
      )
    }
    return .matcher(
      RuntimeMatcher(
        subjectType: nil,
        requirement: name,
        predicate: .prebuilt(call)
      )
    )
  }

  private func literal(
    from value: RuntimeValue,
    at location: DeclarationLocation
  ) throws(RuntimeError) -> LiteralValue {
    switch value {
    case let .string(value): .string(value)
    case let .array(values):
      .strings(
        try values.map { value throws(RuntimeError) in
          guard case let .string(value) = value else {
            throw RuntimeError(
              message: "matcher arrays must contain strings",
              location: location
            )
          }
          return value
        }
      )
    case let .member(value): .member(value.rawValue)
    default:
      throw RuntimeError(
        message: "portable rules do not support this matcher argument",
        location: location
      )
    }
  }
}
