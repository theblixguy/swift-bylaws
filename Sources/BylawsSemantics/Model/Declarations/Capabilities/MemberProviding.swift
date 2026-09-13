/// A declaration that contains member declarations.
public protocol MemberProviding: Sendable {
  /// The stored and computed properties declared directly in this type.
  var properties: MemberCollection<Property> { get }

  /// The functions declared directly in this type.
  var functions: MemberCollection<Function> { get }

  /// The initialisers declared directly in this type.
  var initializers: MemberCollection<Initializer> { get }
}
