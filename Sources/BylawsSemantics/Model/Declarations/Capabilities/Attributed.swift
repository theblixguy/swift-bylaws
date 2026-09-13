/// A declaration that can carry attributes.
public protocol Attributed: Sendable {
  /// The attributes, as written.
  var attributes: [Attribute] { get }
}

extension Attributed {
  /// Whether the declaration bears the attribute `name`.
  ///
  /// The `@` sigil is optional. `"@Published"` and `"Published"` are the
  /// same query.
  public func hasAttribute(_ name: String) -> Bool {
    attribute(named: name) != nil
  }

  /// The attribute named `name`, or `nil` when the declaration does not bear it.
  ///
  /// Accepts the name with or without the `@` sigil.
  public func attribute(named name: String) -> Attribute? {
    let plain = name.hasPrefix("@") ? String(name.dropFirst()) : name
    return attributes.first { $0.name == plain }
  }
}
