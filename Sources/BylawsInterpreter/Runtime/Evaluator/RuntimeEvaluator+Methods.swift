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
      guard case let .model(.check(.location(location))) =
        try arguments
          .value(at: 0)
      else {
        throw RuntimeError(
          message: "findings takes one DeclarationLocation",
          location: arguments.location
        )
      }
      return .findings(result.findings(reportedAt: location))
    }
    let api = receiver.runtimeReceiver.flatMap {
      let receiver = $0
      return SupportedAPI.Member(rawValue: name.rawValue).flatMap {
        SupportedAPI.runtimeMethod(named: $0, on: receiver)
      }
    }
    try requireEffects(of: api, at: arguments.location, state: state)
    if name == .replacement, let elements = receiver.sequenceElements {
      return try await layoutReplacement(
        elements: elements,
        arguments: arguments,
        state: &state
      )
    }
    if name == .violations, case let .selection(selection) = receiver,
       arguments.hasLabels([nil, nil]) || arguments.hasLabels([nil, .changes])
    {
      return try await correctionCheck(
        selection: selection,
        arguments: arguments,
        state: &state
      )
    }
    switch receiver {
    case let .sourceSlice(value):
      if name == .replacement,
         case let .member(literal)? = arguments.values.first?.value,
         literal.owners.contains(.sourceWhitespace)
      {
        try requireEffects(
          of: api, canThrow: true, at: arguments.location, state: state
        )
      }
      return try sourceMethod(name, value: value, arguments: arguments)
    case let .violations(value) where name == .withFix:
      return try await attachingFixes(
        to: value, arguments: arguments, state: &state
      )
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
        values: values[...],
        preservesSet: false,
        arguments: arguments,
        state: &state
      )
    case let .arraySlice(values):
      return try await collectionMethod(
        name, values: values, preservesSet: false,
        arguments: arguments, state: &state
      )
    case let .set(values):
      return try await collectionMethod(
        name,
        values: values[...],
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
    if name == .lowercased || name == .uppercased {
      try arguments.requireLabels([], for: name)
      return .string(
        name == .lowercased
          ? value.lowercased()
          : value
          .uppercased()
      )
    }
    try arguments.requireLabels([nil], for: name)
    if name == .contains,
       case let .regex(pattern) = try arguments.value(at: 0)
    {
      return .boolean(
        value
          .contains(try pattern.compiled(at: arguments.location))
      )
    }
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
    allowsThrowing: Bool = false,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> Bool {
    let transformed = try await transform(
      callable,
      value: value,
      allowsThrowing: allowsThrowing,
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
    allowsThrowing: Bool = false,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    if case let .function(function) = callable {
      return try await invokeSynchronous(
        function,
        arguments: [value],
        allowsThrowing: allowsThrowing,
        at: function.definition.location,
        state: &state
      )
    }
    if case let .keyPath(components, location) = callable {
      let outerAllowsThrowing = state.synchronousClosureAllowsThrowing
      state.synchronousClosureAllowsThrowing = false
      defer { state.synchronousClosureAllowsThrowing = outerAllowsThrowing }
      state.synchronousClosureDepth += 1
      defer { state.synchronousClosureDepth -= 1 }
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
      allowsThrowing: allowsThrowing,
      state: &state
    )
  }

  func requireEffects(
    of api: SupportedAPI.RuntimeMemberAPI?,
    canThrow: Bool = false,
    at location: DeclarationLocation,
    state: RuntimeEvaluationState
  ) throws(RuntimeError) {
    guard state.synchronousClosureDepth > 0 else { return }
    if api?.canSuspend == true {
      throw RuntimeError(
        message: "a synchronous closure cannot suspend", location: location
      )
    }
    if api?.canThrow == true || canThrow,
       !state.synchronousClosureAllowsThrowing
    {
      throw RuntimeError(
        message:
        "a nonthrowing body cannot call a throwing API. Use a throwing function or fix closure.",
        location: location
      )
    }
  }

  func invokeSynchronous(
    _ function: RuntimeFunction,
    arguments: [RuntimeValue],
    allowsThrowing: Bool = false,
    at location: DeclarationLocation,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    let parameters = function.definition.parameters
    guard parameters.count == arguments.count else {
      throw RuntimeError(
        message:
        "'\(function.definition.name)' takes \(argumentCountDescription(parameters.count))",
        location: location
      )
    }
    let outerAllowsThrowing = state.synchronousClosureAllowsThrowing
    state.synchronousClosureAllowsThrowing = allowsThrowing
    state.synchronousClosureDepth += 1
    defer {
      state.synchronousClosureDepth -= 1
      state.synchronousClosureAllowsThrowing = outerAllowsThrowing
    }
    return try await invoke(
      .function(function),
      arguments: zip(parameters, arguments).map { ($0.externalName, $1) },
      trailingClosure: nil,
      at: location,
      state: &state
    )
  }

  func invokeSynchronous(
    _ closure: RuntimeClosure,
    arguments: [RuntimeValue],
    kind: String,
    allowsThrowing: Bool = false,
    builder: RuntimeBuilder? = nil,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    guard !closure.definition.usesAwait,
          allowsThrowing || !closure.definition.usesTry
    else {
      throw RuntimeError(
        message: allowsThrowing
          ? "a \(kind) closure must be synchronous"
          : "a \(kind) closure must be synchronous and nonthrowing",
        location: closure.definition.location
      )
    }
    let outerAllowsThrowing = state.synchronousClosureAllowsThrowing
    state.synchronousClosureAllowsThrowing = allowsThrowing
    state.synchronousClosureDepth += 1
    defer {
      state.synchronousClosureDepth -= 1
      state.synchronousClosureAllowsThrowing = outerAllowsThrowing
    }
    return try await invoke(
      closure,
      arguments: arguments,
      builder: builder,
      state: &state
    )
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
