/// A declaration with an access level.
public protocol Visible: Sendable {
  /// The access level of the declaration.
  var visibility: Visibility { get }
}

extension Visible {
  /// Whether the declaration is `public` or `open`.
  public var isPublic: Bool {
    visibility >= .public
  }
}
