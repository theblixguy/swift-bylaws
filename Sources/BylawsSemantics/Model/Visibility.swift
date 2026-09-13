/// The access level of a declaration, ordered from least to most visible.
public enum Visibility: String, CaseIterable, Comparable, Sendable, Hashable,
  Codable
{
  /// Access from the enclosing declaration and extensions in the same file.
  case `private`

  /// Access from declarations in the same file.
  case `fileprivate`

  /// Access from declarations in the same module.
  case `internal`

  /// Access from declarations in the same package.
  case package

  /// Access from declarations in any module.
  case `public`

  /// Public access that permits subclassing and overrides in another module.
  case open

  /// Returns whether the left access level is less visible than the right.
  public static func < (lhs: Visibility, rhs: Visibility) -> Bool {
    guard lhs != rhs else { return false }
    return allCases.first { $0 == lhs || $0 == rhs } == lhs
  }
}
