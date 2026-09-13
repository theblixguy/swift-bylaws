import BylawsCore
import BylawsSemantics

extension RuntimeEvaluator {
  func memberMatcher(
    _ method: SupportedAPI.Method, types: [SupportedAPI.RuntimeType],
    arguments: RuntimeArguments
  ) throws(RuntimeError) -> RuntimeValue {
    try arguments.requireLabels([nil, .matching], for: method)
    guard types.count == 1, case let .model(subject) = types[0],
          case let .keyPath(path, location) = try arguments.value(at: 0),
          [.all, .any, .none].contains(method)
    else {
      throw RuntimeError(
        message: "Matcher takes a subject type and a key path to its members",
        location: arguments.location
      )
    }
    let child = try matcherValue(
      from: arguments.value(at: 1),
      location: arguments.location
    )
    var resolver = RuntimeTypeResolver(
      environment: [:],
      reportsDiagnostics: false
    )
    let element = resolver.resolveKeyPath(
      path,
      input: .model(subject),
      expectedResult: nil,
      at: location
    ).sequenceElement
    let family = SupportedAPI.DeclarationFamily.allCases.first {
      SupportedAPI.ModelType(declarationFamily: $0)
        .map(SupportedAPI.RuntimeType.model) == element
    }
    let childRequirement = family
      .map { requirement(of: child, for: $0) } ?? child.requirement
    let matcher = RuntimeMatcher(
      subjectType: subject,
      requirement: "have \(method == .all ? "all" : "any") selected members \(childRequirement)",
      predicate: .members(
        all: method == .all,
        path: path,
        matcher: child,
        location: location
      )
    )
    return .matcher(method == .none
      ? RuntimeMatcher(
        subjectType: subject,
        requirement: "not \(matcher.requirement)",
        predicate: .not(matcher)
      )
      : matcher)
  }

  func memberMatch(
    all: Bool, path: [SupportedAPI.Member], matcher: RuntimeMatcher,
    value: RuntimeModelValue, location: DeclarationLocation,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError)
    -> (matches: Bool, witness: DeclarationLocation?)
  {
    let selected = try await transform(
      .keyPath(path, location),
      value: .model(value),
      state: &state
    )
    guard let members = selected.sequenceElements else {
      throw RuntimeError(
        message: "the key path must select a sequence of members",
        location: location
      )
    }
    for member in members {
      try step(at: location, state: &state)
      guard case let .model(model) = member else {
        throw RuntimeError(
          message: "the sequence must contain declaration members",
          location: location
        )
      }
      let result = try await match(matcher, value: model, state: &state)
      if result.matches != all {
        return (result.matches, result.witness ?? model.offender?.location)
      }
    }
    return (all, nil)
  }
}
