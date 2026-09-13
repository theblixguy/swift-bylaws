/// A named class, struct, enum or actor declaration.
public protocol TypeDeclaration: Declaration, Visible, Attributed,
  InheritanceProviding, MemberProviding
{
  /// The qualified name of the enclosing type, when this type is nested.
  var enclosingTypeName: String? { get }

  /// Whether the declaration is marked `nonisolated`.
  var isNonisolated: Bool { get }

  /// The generic parameters the type declares, in order.
  var genericParameters: [GenericParameter] { get }

  /// The UTF-8 byte range of the declaration in its file.
  var sourceRange: Range<Int> { get }

  /// The declaration's source text, as written.
  var sourceText: String { get }
}

extension TypeDeclaration {
  /// The dot-joined name including enclosing types, such as `Legacy.Helper`.
  public var qualifiedName: String {
    enclosingTypeName.map { "\($0).\(name)" } ?? name
  }
}
