import SwiftParser

package import SwiftSyntax

/// A type as written in source, such as `[Order]?` or `Result<Order, Error>`.
///
/// Array and dictionary shorthand expands: `[Order]` has the name `Array` and
/// one generic argument. Typealiases keep their written names. An omitted
/// annotation yields no type reference.
public struct TypeReference: Sendable, Hashable, Codable {
  /// The type as written, without the surrounding whitespace.
  public let text: String

  /// The nominal name without its module, optionality or generic arguments.
  ///
  /// `[Order]?` reports `Array` and
  /// `Swift.Result<Order, Error>` reports `Result`.
  ///
  /// Tuples, function types and protocol compositions report their written
  /// text instead of a nominal name.
  public let name: String

  /// The generic arguments, in order.
  ///
  /// `[String: Int]` reports the key type and then the value type.
  public let genericArguments: [TypeReference]

  /// Whether the type is written as an optional, with `?` or `!`, or as
  /// `Optional<Wrapped>`.
  public let isOptional: Bool

  /// Whether the type is written with `any`.
  public let isExistential: Bool

  /// Whether the type is written with `some`.
  public let isOpaque: Bool

  /// Whether the type is a function type, such as `(Int) -> String`.
  public let isFunction: Bool

  /// Whether the type is a tuple, such as `(Int, String)`.
  public let isTuple: Bool

  /// Creates a type reference by parsing `text` as a Swift type.
  ///
  /// Invalid text uses itself as the name.
  public init(_ text: String) {
    let trimmed = text.trimmingWhitespace
    self = TypeReference(TypeSyntax.parsed(from: trimmed))
      .renamed(text: trimmed)
  }

  package init(_ type: TypeSyntax) {
    self = TypeReader.read(type)
  }

  package init(
    text: String,
    name: String,
    genericArguments: [TypeReference] = [],
    isOptional: Bool = false,
    isExistential: Bool = false,
    isOpaque: Bool = false,
    isFunction: Bool = false,
    isTuple: Bool = false
  ) {
    self.text = text
    self.name = name
    self.genericArguments = genericArguments
    self.isOptional = isOptional
    self.isExistential = isExistential
    self.isOpaque = isOpaque
    self.isFunction = isFunction
    self.isTuple = isTuple
  }

  /// Whether the type is an array, written as `[Element]` or `Array<Element>`.
  public var isArray: Bool { name == "Array" }

  /// Whether the type is a dictionary, written as `[Key: Value]` or
  /// `Dictionary<Key, Value>`.
  public var isDictionary: Bool { name == "Dictionary" }

  /// Whether the type is a set, written as `Set<Element>`.
  public var isSet: Bool { name == "Set" }

  /// The element type of an array or a set, or `nil` for any other type.
  public var elementType: TypeReference? {
    guard isArray || isSet else { return nil }
    return genericArguments.first
  }

  /// The key type of a dictionary, or `nil` for any other type.
  public var keyType: TypeReference? {
    guard isDictionary else { return nil }
    return genericArguments.first
  }

  /// The value type of a dictionary, or `nil` for any other type.
  public var valueType: TypeReference? {
    guard isDictionary, genericArguments.count == 2 else { return nil }
    return genericArguments.last
  }

  /// Whether the nominal name, or the name of a generic argument at any
  /// depth, is `typeName`.
  ///
  /// `[String: [Order]]` references `Order`, `Array`, `Dictionary` and
  /// `String`.
  public func references(_ typeName: String) -> Bool {
    if name == typeName { return true }
    return genericArguments.contains { $0.references(typeName) }
  }

  func renamed(text: String) -> TypeReference {
    TypeReference(
      text: text,
      name: name.isEmpty ? text : name,
      genericArguments: genericArguments,
      isOptional: isOptional,
      isExistential: isExistential,
      isOpaque: isOpaque,
      isFunction: isFunction,
      isTuple: isTuple
    )
  }

  fileprivate func wrapped(
    in node: some SyntaxProtocol,
    isOptional: Bool = false,
    isExistential: Bool = false,
    isOpaque: Bool = false
  ) -> TypeReference {
    TypeReference(
      text: node.trimmedDescription,
      name: name,
      genericArguments: genericArguments,
      isOptional: self.isOptional || isOptional,
      isExistential: self.isExistential || isExistential,
      isOpaque: self.isOpaque || isOpaque,
      isFunction: isFunction,
      isTuple: isTuple
    )
  }
}

extension TypeReference: ExpressibleByStringLiteral {
  /// Creates a type reference by parsing a string literal as a Swift type.
  public init(stringLiteral value: String) {
    self.init(value)
  }
}

extension TypeReference: CustomStringConvertible {
  /// The type as written.
  public var description: String { text }
}

private enum TypeReader {
  static func read(_ type: TypeSyntax) -> TypeReference {
    // Plain identifiers avoid the syntax-node walk needed for rendering.
    if let identifier = type.as(IdentifierTypeSyntax.self),
       identifier.genericArgumentClause == nil
    {
      let name = identifier.name.text
      return TypeReference(text: name, name: name)
    }

    if let attributed = type.as(AttributedTypeSyntax.self) {
      return read(attributed.baseType).wrapped(in: type)
    }
    if let optional = type.as(OptionalTypeSyntax.self) {
      return read(optional.wrappedType).wrapped(in: type, isOptional: true)
    }
    if let optional = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
      return read(optional.wrappedType).wrapped(in: type, isOptional: true)
    }
    if let constrained = type.as(SomeOrAnyTypeSyntax.self) {
      let isAny = constrained.someOrAnySpecifier.text == "any"
      return read(constrained.constraint).wrapped(
        in: type, isExistential: isAny, isOpaque: !isAny
      )
    }
    if let array = type.as(ArrayTypeSyntax.self) {
      return TypeReference(
        text: type.trimmedDescription,
        name: "Array",
        genericArguments: [read(array.element)]
      )
    }
    if let dictionary = type.as(DictionaryTypeSyntax.self) {
      return TypeReference(
        text: type.trimmedDescription,
        name: "Dictionary",
        genericArguments: [read(dictionary.key), read(dictionary.value)]
      )
    }
    if let tuple = type.as(TupleTypeSyntax.self) {
      // Parentheses around one unlabelled element group a type. A label makes
      // it a tuple, as in `(name: Order)`.
      if tuple.elements.count == 1, let only = tuple.elements.first,
         only.firstName == nil
      {
        return read(only.type).wrapped(in: type)
      }
      let text = type.trimmedDescription
      return TypeReference(text: text, name: text, isTuple: true)
    }
    if type.is(FunctionTypeSyntax.self) {
      let text = type.trimmedDescription
      return TypeReference(text: text, name: text, isFunction: true)
    }
    if let identifier = type.as(IdentifierTypeSyntax.self) {
      return named(
        identifier.name.text,
        arguments: identifier.genericArgumentClause,
        text: type.trimmedDescription
      )
    }
    if let member = type.as(MemberTypeSyntax.self) {
      return named(
        member.name.text,
        arguments: member.genericArgumentClause,
        text: type.trimmedDescription
      )
    }
    let text = type.trimmedDescription
    return TypeReference(text: text, name: text)
  }

  private static func named(
    _ name: String,
    arguments clause: GenericArgumentClauseSyntax?,
    text: String
  ) -> TypeReference {
    let arguments: [TypeReference] = clause?.arguments
      .compactMap { argument in
        guard case let .type(type) = argument.argument else { return nil }
        return read(type)
      } ?? []
    if name == "Optional", let wrapped = arguments.first {
      return TypeReference(
        text: text,
        name: wrapped.name,
        genericArguments: wrapped.genericArguments,
        isOptional: true,
        isExistential: wrapped.isExistential,
        isOpaque: wrapped.isOpaque,
        isFunction: wrapped.isFunction,
        isTuple: wrapped.isTuple
      )
    }
    return TypeReference(text: text, name: name, genericArguments: arguments)
  }
}

extension TypeSyntax {
  // SwiftParser accepts only files. A declaration provides the required
  // context for a standalone type.
  fileprivate static func parsed(from text: String) -> TypeSyntax {
    let tree = Parser.parse(source: "let _:\(text)")
    guard let binding = tree.statements.first?.item
      .as(VariableDeclSyntax.self)?.bindings.first,
      let annotation = binding.typeAnnotation
    else { return TypeSyntax(MissingTypeSyntax(placeholder: .identifier(""))) }
    return annotation.type
  }
}

extension String {
  fileprivate var trimmingWhitespace: String {
    var text = Substring(self)
    while let first = text.first, first.isWhitespace {
      text = text.dropFirst()
    }
    while let last = text.last, last.isWhitespace { text = text.dropLast() }
    return String(text)
  }
}
