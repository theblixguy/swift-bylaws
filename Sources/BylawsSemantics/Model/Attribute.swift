/// One attribute on a declaration, as written in source.
public struct Attribute: Sendable, Hashable, Codable {
  /// The attribute name without the `@` sigil, such as `Test` or `MainActor`.
  public let name: String

  /// The raw text between the attribute's parentheses.
  ///
  /// `nil` indicates an attribute without arguments. For
  /// `@Test("Adds one item", .tags(.shoppingCart))`, the value is
  /// `"Adds one item", .tags(.shoppingCart)`.
  public let arguments: String?

  /// Creates an attribute from its source spelling.
  public init(name: String, arguments: String? = nil) {
    self.name = name
    self.arguments = arguments
  }
}

extension Attribute: CustomStringConvertible {
  /// The attribute as written, such as `@MainActor`.
  public var description: String {
    if let arguments {
      return "@\(name)(\(arguments))"
    }
    return "@\(name)"
  }
}
