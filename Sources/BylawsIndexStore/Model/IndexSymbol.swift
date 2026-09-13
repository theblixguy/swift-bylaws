import CIndexStore

/// One symbol the compiler recorded, such as a type, a function or a
/// property.
public struct IndexSymbol: Sendable, Hashable {
  /// The declaration kind the compiler recorded.
  ///
  /// Later versions may add cases.
  @nonexhaustive
  public enum Kind: Sendable, Hashable {
    /// A module.
    case module
    /// An enum.
    case `enum`
    /// A struct.
    case `struct`
    /// A class.
    case `class`
    /// A protocol.
    case `protocol`
    /// An extension.
    case `extension`
    /// A typealias.
    case `typealias`
    /// A free function.
    case function
    /// A variable or a stored member of a C struct.
    case variable
    /// A method on an instance.
    case instanceMethod
    /// A method on a class, which a subclass can override.
    case classMethod
    /// A method on a type.
    case staticMethod
    /// A property on an instance.
    case instanceProperty
    /// A property on a class, which a subclass can override.
    case classProperty
    /// A property on a type.
    case staticProperty
    /// An initialiser.
    case initializer
    /// A deinitialiser.
    case deinitializer
    /// One case of an enum.
    case enumCase
    /// A parameter of a function, a method or an initialiser.
    case parameter
    /// A kind Bylaws does not model, such as a C macro.
    case other

    init(_ kind: indexstore_symbol_kind_t) {
      self = switch kind {
      case INDEXSTORE_SYMBOL_KIND_MODULE: .module
      case INDEXSTORE_SYMBOL_KIND_ENUM: .enum
      case INDEXSTORE_SYMBOL_KIND_STRUCT: .struct
      case INDEXSTORE_SYMBOL_KIND_CLASS: .class
      case INDEXSTORE_SYMBOL_KIND_PROTOCOL: .protocol
      case INDEXSTORE_SYMBOL_KIND_EXTENSION: .extension
      case INDEXSTORE_SYMBOL_KIND_TYPEALIAS: .typealias
      case INDEXSTORE_SYMBOL_KIND_FUNCTION: .function
      case INDEXSTORE_SYMBOL_KIND_VARIABLE: .variable
      case INDEXSTORE_SYMBOL_KIND_FIELD: .variable
      case INDEXSTORE_SYMBOL_KIND_ENUMCONSTANT: .enumCase
      case INDEXSTORE_SYMBOL_KIND_INSTANCEMETHOD: .instanceMethod
      case INDEXSTORE_SYMBOL_KIND_CLASSMETHOD: .classMethod
      case INDEXSTORE_SYMBOL_KIND_STATICMETHOD: .staticMethod
      case INDEXSTORE_SYMBOL_KIND_INSTANCEPROPERTY: .instanceProperty
      case INDEXSTORE_SYMBOL_KIND_CLASSPROPERTY: .classProperty
      case INDEXSTORE_SYMBOL_KIND_STATICPROPERTY: .staticProperty
      case INDEXSTORE_SYMBOL_KIND_CONSTRUCTOR: .initializer
      case INDEXSTORE_SYMBOL_KIND_DESTRUCTOR: .deinitializer
      case INDEXSTORE_SYMBOL_KIND_PARAMETER: .parameter
      default: .other
      }
    }

    /// Whether the kind names a type that other types can conform to or
    /// inherit from.
    public var isType: Bool {
      switch self {
      case .enum, .struct, .class, .protocol, .typealias: true
      default: false
      }
    }
  }

  /// The compiler's identifier for the symbol, which is stable across
  /// modules and files.
  public let usr: String

  /// The symbol's name, without its module or its enclosing type.
  public let name: String

  /// The declaration kind.
  public let kind: Kind

  /// Creates a symbol with the given identifier, name and kind.
  public init(usr: String, name: String, kind: Kind) {
    self.usr = usr
    self.name = name
    self.kind = kind
  }
}

extension IndexSymbol: CustomStringConvertible {
  public var description: String { "\(name) (\(kind))" }
}
