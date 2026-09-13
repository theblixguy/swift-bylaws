/// A class, struct, enum or actor declaration, as written in one source
/// file.
///
/// Use this type for a rule that applies to every nominal type. Switch over
/// its cases for kind-specific data such as an enum's cases.
public enum NominalType: NominalTypeDeclaration {
  /// A `class` declaration.
  case `class`(Class)

  /// A `struct` declaration.
  case `struct`(Struct)

  /// An `enum` declaration.
  case `enum`(Enum)

  /// An `actor` declaration.
  case `actor`(Actor)

  /// Whether the declaration is a class.
  public var isClass: Bool {
    if case .class = self { true } else { false }
  }

  /// Whether the declaration is a struct.
  public var isStruct: Bool {
    if case .struct = self { true } else { false }
  }

  /// Whether the declaration is an enum.
  public var isEnum: Bool {
    if case .enum = self { true } else { false }
  }

  /// Whether the declaration is an actor.
  public var isActor: Bool {
    if case .actor = self { true } else { false }
  }

  /// The keyword the declaration is written with: `class`, `struct`,
  /// `enum` or `actor`.
  public var keyword: String {
    switch self {
    case .class: "class"
    case .struct: "struct"
    case .enum: "enum"
    case .actor: "actor"
    }
  }

  /// The data of the wrapped declaration.
  public var storage: NominalTypeStorage {
    switch self {
    case let .class(declaration): declaration.storage
    case let .struct(declaration): declaration.storage
    case let .enum(declaration): declaration.storage
    case let .actor(declaration): declaration.storage
    }
  }
}

extension NominalType {
  /// Returns whether two nominal types have the same kind and source identity.
  public static func == (lhs: NominalType, rhs: NominalType) -> Bool {
    lhs.keyword == rhs.keyword
      && lhs.name == rhs.name
      && lhs.location == rhs.location
  }

  /// Hashes the nominal type's kind, name and source position.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(keyword)
    hasher.combine(name)
    hasher.combine(location)
  }
}

extension NominalType: CustomStringConvertible {
  /// The keyword and name, formatted as `class Name`.
  public var summary: String { "\(keyword) \(name)" }
}
