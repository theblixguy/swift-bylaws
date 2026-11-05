package struct SourceListLayout<Element: SourceProviding>: Sendable {
  package enum Directive: Sendable {
    case group(Group<Element>)
    case separator(SourceWhitespace)
    case conditional(SourceListSeparator<Element>, SourceWhitespace)
  }

  package let directives: [Directive]
}

package struct SourceListSeparator<Element: Sendable>: Sendable {
  enum Condition: Sendable {
    case always
    case between(
      @Sendable (Element) throws -> Bool,
      @Sendable (Element) throws -> Bool
    )
    case before(@Sendable (Element) throws -> Bool)
    case after(@Sendable (Element) throws -> Bool)
  }

  let condition: Condition

  func matches(previous: Element, next: Element) throws -> Bool {
    switch condition {
    case .always: true
    case let .between(first, second):
      try (first(previous) && second(next)) || (first(next) && second(previous))
    case let .before(predicate): try predicate(next)
    case let .after(predicate): try predicate(previous)
    }
  }
}
