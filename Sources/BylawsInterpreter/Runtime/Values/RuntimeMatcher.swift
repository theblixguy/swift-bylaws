import BylawsSemantics

struct RuntimeMatcher: Sendable {
  indirect enum Predicate: Sendable {
    case closure(RuntimeClosure)
    case prebuilt(ParsedCall)
    case keyPath([SupportedAPI.Member], DeclarationLocation)
    case members(
      all: Bool,
      path: [SupportedAPI.Member],
      matcher: RuntimeMatcher,
      location: DeclarationLocation
    )
    case and(RuntimeMatcher, RuntimeMatcher)
    case or(RuntimeMatcher, RuntimeMatcher)
    case not(RuntimeMatcher)
  }

  let subjectType: SupportedAPI.ModelType?
  let requirement: String
  let predicate: Predicate
}
