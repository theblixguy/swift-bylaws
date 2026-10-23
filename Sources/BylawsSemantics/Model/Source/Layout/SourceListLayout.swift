/// A grouping or spacing policy for a captured source list.
public struct SourceListLayout<Element: SourceProviding>: Sendable {
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

/// Builds a grouping or conditional spacing policy for an input source list.
@resultBuilder
public enum SourceListLayoutBuilder<Element: SourceProviding> {
  /// Combines the policies in their written order.
  public static func buildBlock(
    _ components: SourceListLayout<Element>...
  ) -> SourceListLayout<Element> {
    SourceListLayout(directives: components.flatMap(\.directives))
  }

  /// Adds a first-match group.
  public static func buildExpression(_ group: Group<Element>)
    -> SourceListLayout<Element>
  {
    SourceListLayout(directives: [.group(group)])
  }

  /// Adds a blank line between nonempty groups.
  public static func buildExpression(_ line: BlankLine<Never>)
    -> SourceListLayout<Element>
  {
    SourceListLayout(directives: [.separator(.blankLine)])
  }

  /// Adds a line break between nonempty groups.
  public static func buildExpression(_ line: Newline<Never>)
    -> SourceListLayout<Element>
  {
    SourceListLayout(directives: [.separator(.newline)])
  }

  /// Adds a conditional blank line between adjacent input elements.
  public static func buildExpression(_ line: BlankLine<Element>)
    -> SourceListLayout<Element>
  {
    SourceListLayout(directives: [.conditional(line.separator, .blankLine)])
  }

  /// Adds a conditional line break between adjacent input elements.
  public static func buildExpression(_ line: Newline<Element>)
    -> SourceListLayout<Element>
  {
    SourceListLayout(directives: [.conditional(line.separator, .newline)])
  }

  /// Includes a policy when its condition is true.
  public static func buildOptional(_ component: SourceListLayout<Element>?)
    -> SourceListLayout<Element>
  {
    component ?? SourceListLayout(directives: [])
  }

  /// Includes the first branch of a conditional policy.
  public static func buildEither(first component: SourceListLayout<Element>)
    -> SourceListLayout<Element> { component }

  /// Includes the second branch of a conditional policy.
  public static func buildEither(second component: SourceListLayout<Element>)
    -> SourceListLayout<Element> { component }

  /// Combines policies produced by a loop.
  public static func buildArray(_ components: [SourceListLayout<Element>])
    -> SourceListLayout<Element>
  {
    SourceListLayout(directives: components.flatMap(\.directives))
  }

  /// Includes a policy for an available API.
  public static func buildLimitedAvailability(
    _ component: SourceListLayout<Element>
  )
    -> SourceListLayout<Element> { component }
}
