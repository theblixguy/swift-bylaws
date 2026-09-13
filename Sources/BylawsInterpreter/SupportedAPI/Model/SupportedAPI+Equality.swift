extension SupportedAPI.RuntimeType {
  var supportsHashing: Bool {
    switch self {
    case .model(.syntaxTriviaPiece), .violations(.syntaxTriviaPiece):
      false
    case let .dictionary(_, value): value.supportsHashing
    case let .array(element), let .set(element), let .optional(element),
         let .manifestList(element):
      element.supportsHashing
    default:
      supportsEquality
    }
  }

  var supportsEquality: Bool {
    switch self {
    case .url: true
    case let .dictionary(_, value): value.supportsEquality
    case .unknown, .boolean, .integer, .double, .string, .integerRange,
         .staticMember, .symbolRoles, .model, .codebase, .layering, .violations,
         .dependencyGroup:
      true
    case let .array(element), let .set(element), let .optional(element),
         let .manifestList(element):
      element.supportsEquality
    default:
      false
    }
  }
}
