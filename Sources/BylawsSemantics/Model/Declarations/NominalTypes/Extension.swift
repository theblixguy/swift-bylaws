/// An `extension` declaration, as written in one source file.
public struct Extension: Named, Located, Visible, Attributed, Hashable,
  Codable
{
  /// The extended type's name, as written, such as `HomeViewModel`
  /// or `Legacy.Helper`.
  public let extendedTypeName: String

  /// The type names the extension adds conformances to.
  public let inheritedTypes: [String]

  /// The access level written on the extension.
  ///
  /// An unmarked extension reports `internal`.
  public let visibility: Visibility

  /// The attributes, such as `@MainActor`.
  public let attributes: [Attribute]

  public package(set) var location: DeclarationLocation

  /// The type names the extension's conformances inherit from, including
  /// the conformances themselves.
  ///
  /// The list is empty until the codebase resolves inheritance.
  public package(set) var allInheritedTypes: [String] = []

  /// Creates an extension model.
  public init(
    extendedTypeName: String,
    inheritedTypes: [String],
    visibility: Visibility = .internal,
    attributes: [Attribute] = [],
    location: DeclarationLocation
  ) {
    self.extendedTypeName = extendedTypeName
    self.inheritedTypes = inheritedTypes
    self.visibility = visibility
    self.attributes = attributes
    self.location = location
  }

  /// The extended type's name.
  public var name: String { extendedTypeName }

  /// The last component of the extended type's name.
  public var simpleExtendedTypeName: String {
    extendedTypeName.split(separator: ".").last
      .map(String.init) ?? extendedTypeName
  }
}

extension Extension: Summarised, CustomStringConvertible {
  /// The extended type, formatted as `extension Name`.
  public var summary: String { "extension \(extendedTypeName)" }

  /// The summary and location, formatted as
  /// `extension Name (File.swift:line)`.
  public var description: String {
    "\(summary) (\(location.fileName):\(location.line))"
  }
}
