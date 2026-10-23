/// An empty line between groups or matching adjacent source elements.
public struct BlankLine<Element: Sendable>: Sendable {
  package let separator: SourceListSeparator<Element>

  /// Creates an unconditional separator between nonempty groups or explicit source.
  public init() where Element == Never {
    separator = SourceListSeparator(condition: .always)
  }

  /// Creates a separator between adjacent elements that match in either order.
  public init(
    between first: @escaping @Sendable (Element) throws -> Bool,
    and second: @escaping @Sendable (Element) throws -> Bool
  ) where Element: SourceProviding {
    separator = SourceListSeparator(condition: .between(first, second))
  }

  /// Creates a separator before a matching element that has a preceding element.
  public init(before predicate: @escaping @Sendable (Element) throws -> Bool)
    where Element: SourceProviding
  {
    separator = SourceListSeparator(condition: .before(predicate))
  }

  /// Creates a separator after a matching element that has a following element.
  public init(after predicate: @escaping @Sendable (Element) throws -> Bool)
    where Element: SourceProviding
  {
    separator = SourceListSeparator(condition: .after(predicate))
  }
}
