/// One case of an `enum` declaration.
public struct EnumCase: Declaration, Documented, Codable {
  public let name: String

  /// Whether the case is marked `indirect`.
  public let isIndirect: Bool

  /// The raw value as written, such as `"home"` in `case home = "home"`, or
  /// `nil` when absent.
  public let rawValue: String?

  /// The qualified name of the enum that declares this case.
  public let enclosingTypeName: String?

  /// The documentation comment above the case declaration, as written.
  public let documentation: String?

  public package(set) var location: DeclarationLocation

  /// Creates an enum-case model.
  public init(
    name: String,
    isIndirect: Bool = false,
    rawValue: String? = nil,
    enclosingTypeName: String?,
    documentation: String? = nil,
    location: DeclarationLocation
  ) {
    self.name = name
    self.isIndirect = isIndirect
    self.rawValue = rawValue
    self.enclosingTypeName = enclosingTypeName
    self.documentation = documentation
    self.location = location
  }
}

extension EnumCase: CustomStringConvertible {}
