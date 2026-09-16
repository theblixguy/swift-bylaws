extension QueryExpression {
  var canUseDeclarationsAsWritten: Bool {
    guard filters.allSatisfy({ filter in
      switch SupportedAPI.filter(named: filter.name)?.id {
      case .named, .suffixed, .prefixed, .excluding,
           .under, .outside, .nameMatching: true
      default: false
      }
    }) else { return false }
    return switch check {
    case .outsidePaths: true
    case let .of(expression), let .matching(expression):
      expression.canUseDeclarationsAsWritten
    }
  }
}

extension MatcherExpression {
  fileprivate var canUseDeclarationsAsWritten: Bool {
    switch self {
    case let .leaf(call):
      switch SupportedAPI.matcher(named: call.name)?.id {
      case .named, .suffixed, .prefixed, .nameMatching,
           .isFinal, .isPublic, .hasVisibility, .hasAttribute,
           .hasDocumentation, .isClass, .isStruct, .isEnum, .isActor:
        true
      default:
        false
      }
    case let .not(expression):
      expression.canUseDeclarationsAsWritten
    case let .and(left, right), let .or(left, right):
      left.canUseDeclarationsAsWritten && right.canUseDeclarationsAsWritten
    }
  }
}
