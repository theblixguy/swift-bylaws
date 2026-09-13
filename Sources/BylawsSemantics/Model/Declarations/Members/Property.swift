/// A `let` or `var` declaration, as written in one source file.
public struct Property: Declaration, Visible, Attributed, Documented, Codable {
  public let name: String

  /// The type annotation, or `nil` when the type is inferred.
  ///
  /// Bylaws cannot infer an omitted property type from source syntax.
  public let type: TypeReference?

  /// The type annotation, as written, or `nil` when the type is inferred.
  public var typeName: String? { type?.text }

  /// Whether the property is declared with `let`.
  public let isConstant: Bool

  /// Whether the property is `static` or `class`-scoped.
  public let isStatic: Bool

  /// The `weak` or `unowned` modifier, or `nil` for a strong reference.
  public let ownership: Ownership?

  /// Whether the property is marked `lazy`.
  public let isLazy: Bool

  /// Whether the property is marked `dynamic`.
  public let isDynamic: Bool

  /// Whether the property is marked `nonisolated`.
  public let isNonisolated: Bool

  /// Whether the property is marked `nonisolated(unsafe)`.
  public let isNonisolatedUnsafe: Bool

  public let visibility: Visibility
  public let attributes: [Attribute]

  /// The qualified name of the type that declares this property, or `nil`
  /// for top-level properties.
  public let enclosingTypeName: String?

  /// The call expressions in the property's initialiser value and in
  /// its accessors.
  public package(set) var calls: [FunctionCall]

  public let documentation: String?
  public package(set) var location: DeclarationLocation

  /// Creates a property model.
  public init(
    name: String,
    type: TypeReference?,
    isConstant: Bool,
    isStatic: Bool,
    ownership: Ownership? = nil,
    isLazy: Bool = false,
    isDynamic: Bool = false,
    isNonisolated: Bool = false,
    isNonisolatedUnsafe: Bool = false,
    visibility: Visibility,
    attributes: [Attribute] = [],
    enclosingTypeName: String? = nil,
    calls: [FunctionCall] = [],
    documentation: String? = nil,
    location: DeclarationLocation
  ) {
    self.name = name
    self.type = type
    self.isConstant = isConstant
    self.isStatic = isStatic
    self.ownership = ownership
    self.isLazy = isLazy
    self.isDynamic = isDynamic
    self.isNonisolated = isNonisolated
    self.isNonisolatedUnsafe = isNonisolatedUnsafe
    self.visibility = visibility
    self.attributes = attributes
    self.enclosingTypeName = enclosingTypeName
    self.calls = calls
    self.documentation = documentation
    self.location = location
  }

  /// Whether the property is declared `weak`.
  public var isWeak: Bool { ownership == .weak }

  /// Whether any call in the property's initialiser value or accessors
  /// references `identifier`.
  ///
  /// Use the ``calls`` property for the call declarations themselves.
  public func calls(_ identifier: String) -> Bool {
    calls.contains { $0.references(identifier) }
  }
}

extension Property: CustomStringConvertible {}
