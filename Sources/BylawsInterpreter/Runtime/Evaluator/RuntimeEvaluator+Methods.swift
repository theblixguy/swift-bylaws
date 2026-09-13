import BylawsCore
import BylawsSemantics
import Foundation

extension RuntimeEvaluator {
  func invoke(
    method name: SupportedAPI.Method,
    of receiver: RuntimeValue,
    arguments: RuntimeArguments,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    if name == .findings, let result = receiver.ruleResult {
      try arguments.requireLabels([.reportedAt], for: name)
      guard case let .model(.check(.location(location))) = try arguments
        .value(at: 0)
      else {
        throw RuntimeError(
          message: "findings takes one DeclarationLocation",
          location: arguments.location
        )
      }
      return .findings(result.findings(reportedAt: location))
    }
    if state.synchronousClosureDepth > 0,
       case .codebase = receiver
    {
      throw RuntimeError(
        message: "a synchronous closure cannot suspend",
        location: arguments.location
      )
    }
    switch receiver {
    case let .url(value) where name == .deletingLastPathComponent:
      return .url(value.deletingLastPathComponent())
    case let .dictionary(values) where name == .mapValues:
      return try await mapDictionary(
        values,
        arguments: arguments,
        state: &state
      )
    case let .genericType("Matcher", types):
      return try memberMatcher(name, types: types, arguments: arguments)
    case let .array(values):
      return try await collectionMethod(
        name,
        values: values,
        preservesSet: false,
        arguments: arguments,
        state: &state
      )
    case let .set(values):
      return try await collectionMethod(
        name,
        values: values,
        preservesSet: true,
        arguments: arguments,
        state: &state
      )
    case let .string(value):
      return try stringMethod(name, value: value, arguments: arguments)
    case let .integerRange(value):
      try arguments.requireLabels([nil], for: name)
      guard name == .contains else {
        throw RuntimeError(
          message: "'\(name.rawValue)' is not a supported Range method",
          location: arguments.location
        )
      }
      return .boolean(value.contains(try arguments.integer(at: 0)))
    case let .selection(selection):
      return try await selectionMethod(
        name,
        selection: selection,
        arguments: arguments,
        state: &state
      )
    case let .codebase(codebase):
      return try await codebaseMethod(
        name,
        codebase: codebase,
        arguments: arguments
      )
    case let .projectIndex(index):
      return try await projectIndexMethod(
        name,
        index: index,
        arguments: arguments
      )
    case let .symbolRoles(roles):
      try arguments.requireLabels([nil], for: name)
      guard name == .contains,
            case let .member(roleName) = try arguments.value(at: 0),
            let role = RuntimeSymbolRole(rawValue: roleName.rawValue)
      else {
        throw RuntimeError(
          message: "SymbolRole supports 'contains' with a static role",
          location: arguments.location
        )
      }
      return .boolean(roles.contains(role))
    case let .model(value):
      return try await modelMethod(
        name,
        value: value,
        arguments: arguments,
        state: &state
      )
    default:
      throw RuntimeError(
        message: "'\(name.rawValue)' is not a supported method of this value",
        location: arguments.location
      )
    }
  }

  private func stringMethod(
    _ name: SupportedAPI.Method,
    value: String,
    arguments: RuntimeArguments
  ) throws(RuntimeError) -> RuntimeValue {
    try arguments.requireLabels([nil], for: name)
    let argument = try arguments.string(at: 0)
    return switch name {
    case .hasPrefix: .boolean(value.hasPrefix(argument))
    case .hasSuffix: .boolean(value.hasSuffix(argument))
    case .contains: .boolean(value.contains(argument))
    default:
      throw RuntimeError(
        message: "'\(name.rawValue)' is not a supported String method",
        location: arguments.location
      )
    }
  }

  func predicate(
    _ callable: RuntimeValue,
    value: RuntimeValue,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> Bool {
    let transformed = try await transform(
      callable,
      value: value,
      state: &state
    )
    guard case let .boolean(result) = transformed else {
      throw RuntimeError(
        message: "collection predicate must return Bool",
        location: keyPathLocation(callable) ?? globalsLocation
      )
    }
    return result
  }

  func transform(
    _ callable: RuntimeValue,
    value: RuntimeValue,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    if case let .function(function) = callable {
      state.synchronousClosureDepth += 1
      defer { state.synchronousClosureDepth -= 1 }
      return try await invoke(
        callable,
        arguments: [(
          function.definition.parameters.first?.externalName,
          value
        )],
        trailingClosure: nil,
        at: function.definition.location,
        state: &state
      )
    }
    if case let .keyPath(components, location) = callable {
      var value = value
      for component in components {
        value = try await member(
          named: component,
          of: value,
          at: location,
          state: &state
        )
      }
      return value
    }
    guard case let .closure(closure) = callable else {
      throw RuntimeError(
        message: "this collection operation takes a closure, function or key path",
        location: globalsLocation
      )
    }
    return try await invokeSynchronous(
      closure,
      arguments: [value],
      kind: "collection",
      state: &state
    )
  }

  func invokeSynchronous(
    _ closure: RuntimeClosure,
    arguments: [RuntimeValue],
    kind: String,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    guard !closure.definition.usesAwait, !closure.definition.usesTry else {
      throw RuntimeError(
        message: "a \(kind) closure must be synchronous and nonthrowing",
        location: closure.definition.location
      )
    }
    state.synchronousClosureDepth += 1
    defer { state.synchronousClosureDepth -= 1 }
    return try await invoke(closure, arguments: arguments, state: &state)
  }

  func matcherValue(
    from value: RuntimeValue,
    location: DeclarationLocation
  ) throws(RuntimeError) -> RuntimeMatcher {
    switch value {
    case let .matcher(matcher): matcher
    case let .keyPath(members, location):
      RuntimeMatcher(
        subjectType: nil,
        requirement: "have \(members.last?.rawValue ?? "value") be true",
        predicate: .keyPath(members, location)
      )
    case let .member(name):
      try prebuiltMatcher(
        named: name.rawValue,
        arguments: RuntimeArguments(values: [], location: location)
      ).matcher(at: location)
    default:
      throw RuntimeError(
        message: "this value is not a Matcher",
        location: location
      )
    }
  }

  private func keyPathLocation(_ value: RuntimeValue) -> DeclarationLocation? {
    guard case let .keyPath(_, location) = value else { return nil }
    return location
  }

  private var globalsLocation: DeclarationLocation {
    DeclarationLocation.start(of: "<interpreted rule>")
  }
}
