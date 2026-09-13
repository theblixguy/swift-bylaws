/// An `import` declaration, as written in one source file.
public struct Import: Declaration, Visible, Attributed, Codable {
  /// The imported module path, as written, such as `Foundation`
  /// or `Foundation.Date`.
  public let name: String

  /// The kind specifier, such as `struct` in `import struct Foundation.Date`,
  /// or `nil` for a whole-module import.
  public let kind: ImportKind?

  /// The access level written on the import.
  ///
  /// An unmarked import reports `internal`.
  public let visibility: Visibility

  /// The attributes, such as `@preconcurrency` or `@testable`.
  public let attributes: [Attribute]

  public package(set) var location: DeclarationLocation

  /// Creates an import model.
  public init(
    name: String,
    kind: ImportKind? = nil,
    visibility: Visibility = .internal,
    attributes: [Attribute] = [],
    location: DeclarationLocation
  ) {
    self.name = name
    self.kind = kind
    self.visibility = visibility
    self.attributes = attributes
    self.location = location
  }

  /// The first component of the imported module path.
  public var moduleName: String {
    name.split(separator: ".").first.map(String.init) ?? name
  }

  package func references(_ module: String) -> Bool {
    name == module || moduleName == module
  }
}

/// The declaration kind named in a scoped import, such as
/// `import struct Foundation.Date`.
public enum ImportKind: String, CaseIterable, Sendable, Hashable, Codable {
  /// A structure import.
  case `struct`

  /// A class import.
  case `class`

  /// An actor import.
  case `actor`

  /// An enumeration import.
  case `enum`

  /// A protocol import.
  case `protocol`

  /// A type alias import.
  case `typealias`

  /// A function import.
  case `func`

  /// A variable import.
  case `var`

  /// A constant import.
  case `let`
}

extension Import: CustomStringConvertible {
  /// The statement, formatted as `import Name`.
  public var summary: String { "import \(name)" }
}
