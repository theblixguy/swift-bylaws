/// Builds an ordered list with expressions, conditions and loops.
@resultBuilder
public enum ArrayBuilder<Element> {
  /// Includes one element in the list.
  public static func buildExpression(_ element: Element)
    -> [Element] { [element] }
  /// Includes the elements of an existing list in their current order.
  public static func buildExpression(_ elements: [Element])
    -> [Element] { elements }
  /// Combines the expressions in a block in source order.
  public static func buildBlock(_ components: [Element]...)
    -> [Element] { components.flatMap(\.self) }
  /// Includes the first branch when its condition is true.
  public static func buildEither(first component: [Element])
    -> [Element] { component }
  /// Includes the alternative branch when its condition is false.
  public static func buildEither(second component: [Element])
    -> [Element] { component }
  /// Includes an optional branch, or an empty list when it is absent.
  public static func buildOptional(_ component: [Element]?)
    -> [Element] { component ?? [] }
  /// Combines loop results in iteration order.
  public static func buildArray(_ components: [[Element]])
    -> [Element] { components.flatMap(\.self) }
  /// Includes the selected branch of an availability check.
  public static func buildLimitedAvailability(_ component: [Element])
    -> [Element] { component }
}

extension [Rule] {
  /// Creates a rule list with expressions, conditions and loops.
  public init(@ArrayBuilder<Rule> _ body: () -> [Rule]) {
    self = body()
  }
}
