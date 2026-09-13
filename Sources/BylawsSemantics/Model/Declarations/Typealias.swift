/// A `typealias` declaration, as written in one source file.
public struct Typealias: Declaration, Visible, Attributed, Documented, Codable {
  public let name: String

  /// The aliased type as written, such as `Result<String, Error>`.
  public let aliasedTypeName: String

  public let visibility: Visibility
  public let attributes: [Attribute]

  /// The qualified name of the type that declares this alias, or `nil`
  /// for top-level aliases.
  public let enclosingTypeName: String?

  public let documentation: String?
  public package(set) var location: DeclarationLocation

  /// Creates a typealias model.
  public init(
    name: String,
    aliasedTypeName: String,
    visibility: Visibility,
    attributes: [Attribute] = [],
    enclosingTypeName: String? = nil,
    documentation: String? = nil,
    location: DeclarationLocation
  ) {
    self.name = name
    self.aliasedTypeName = aliasedTypeName
    self.visibility = visibility
    self.attributes = attributes
    self.enclosingTypeName = enclosingTypeName
    self.documentation = documentation
    self.location = location
  }
}

extension Typealias: CustomStringConvertible {}
