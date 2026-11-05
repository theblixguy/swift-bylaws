/// A group of input elements that match its condition.
public struct Group<Element: Sendable>: Sendable {
  package let predicate: @Sendable (Element) throws -> Bool
  package var comparison: (@Sendable (Element, Element) throws -> Bool)?

  /// Creates a group from elements not claimed by an earlier group.
  public init(_ predicate: @escaping @Sendable (Element) throws -> Bool) {
    self.predicate = predicate
  }

  /// Groups elements whose selected property is true.
  public init(_ keyPath: any KeyPath<Element, Bool> & Sendable) {
    self.init { $0[keyPath: keyPath] }
  }

  /// Groups elements whose selected value exists and matches the condition.
  ///
  /// Elements with no selected value remain available to later groups.
  public init<Value>(
    _ keyPath: any KeyPath<Element, Value?> & Sendable,
    where predicate: @escaping @Sendable (Value) throws -> Bool
  ) {
    self.predicate = { element in
      guard let value = element[keyPath: keyPath] else { return false }
      return try predicate(value)
    }
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
