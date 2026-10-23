/// A group of input elements that match its condition.
public struct Group<Element: Sendable>: Sendable {
  package let predicate: @Sendable (Element) throws -> Bool
  package var comparison: (@Sendable (Element, Element) throws -> Bool)?

  /// Creates a group from elements not claimed by an earlier group.
  public init(where predicate: @escaping @Sendable (Element) throws -> Bool) {
    self.predicate = predicate
  }

  /// Returns a group ordered by the comparison, retaining equal elements' order.
  public func sorted(
    by comparison: @escaping @Sendable (Element, Element) throws -> Bool
  ) -> Self {
    var result = self
    result.comparison = comparison
    return result
  }
}
