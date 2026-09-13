import BylawsCore
import BylawsSemantics

extension RuntimeEvaluator {
  func matches(
    _ matcher: RuntimeMatcher,
    value: RuntimeModelValue,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> Bool {
    try await match(matcher, value: value, state: &state).matches
  }

  func match(
    _ matcher: RuntimeMatcher,
    value: RuntimeModelValue,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError)
    -> (matches: Bool, witness: DeclarationLocation?)
  {
    if let subjectType = matcher.subjectType, value.modelType != subjectType {
      throw RuntimeError(
        message: "this Matcher<\(subjectType.rawValue)> does not apply to this value",
        location: matcher.location
      )
    }
    switch matcher.predicate {
    case let .keyPath(path, location):
      let result = try await predicate(
        .keyPath(path, location),
        value: .model(value),
        state: &state
      )
      return (result, nil)
    case let .members(all, path, child, location):
      return try await memberMatch(
        all: all,
        path: path,
        matcher: child,
        value: value,
        location: location,
        state: &state
      )
    case let .closure(closure):
      state.synchronousClosureDepth += 1
      defer { state.synchronousClosureDepth -= 1 }
      let result = try await invoke(
        closure,
        arguments: [.model(value)],
        state: &state
      )
      guard case let .boolean(matches) = result else {
        throw RuntimeError(
          message: "a Matcher predicate must return Bool",
          location: closure.definition.location
        )
      }
      return (matches, nil)
    case let .prebuilt(call):
      return try match(call, value: value)
    case let .and(left, right):
      let left = try await match(left, value: value, state: &state)
      guard left.matches else { return left }
      let right = try await match(right, value: value, state: &state)
      return right.matches ? (true, left.witness ?? right.witness) : right
    case let .or(left, right):
      let left = try await match(left, value: value, state: &state)
      if left.matches { return left }
      return try await match(right, value: value, state: &state)
    case let .not(inner):
      let result = try await match(inner, value: value, state: &state)
      return (!result.matches, result.witness)
    }
  }

  private func match(
    _ call: ParsedCall,
    value: RuntimeModelValue
  ) throws(RuntimeError) -> (matches: Bool, witness: DeclarationLocation?) {
    let family = value.family
    guard let family else {
      throw RuntimeError(
        message: "matchers do not apply to this value",
        location: call.location
      )
    }
    let supported = switch MatcherCompiler.resolve(call, for: family) {
    case let .success(value): value
    case let .failure(diagnostic):
      throw RuntimeError(
        message: diagnostic.message,
        location: diagnostic.location
      )
    }
    guard let result = value.matcherSubject?.match(supported, call) else {
      throw RuntimeError(
        message: "'\(call.name)' does not apply to this value",
        location: call.location
      )
    }
    return result
  }

  func requirement(
    of matcher: RuntimeMatcher,
    for family: SupportedAPI.DeclarationFamily
  ) -> String {
    switch matcher.predicate {
    case let .prebuilt(call):
      prebuiltRequirement(call, family: family) ?? matcher.requirement
    case .closure, .keyPath, .members:
      matcher.requirement
    case let .and(left, right):
      "\(requirement(of: left, for: family)) and \(requirement(of: right, for: family))"
    case let .or(left, right):
      "(\(requirement(of: left, for: family)) or \(requirement(of: right, for: family)))"
    case let .not(inner):
      "not \(requirement(of: inner, for: family))"
    }
  }

  private func prebuiltRequirement(
    _ call: ParsedCall,
    family: SupportedAPI.DeclarationFamily
  ) -> String? {
    guard case let .success(matcher) = MatcherCompiler.resolve(
      call,
      for: family
    ) else { return nil }
    return family.subject.requirement(of: matcher, call)
  }
}

extension RuntimeMatcher {
  fileprivate var location: DeclarationLocation {
    switch predicate {
    case let .keyPath(_, location), let .members(_, _, _, location): location
    case let .closure(closure): closure.definition.location
    case let .prebuilt(call): call.location
    case let .and(left, _), let .or(left, _): left.location
    case let .not(inner): inner.location
    }
  }
}
