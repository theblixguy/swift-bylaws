/// A named declaration that contains a source occurrence.
public struct EnclosingDeclaration: Named, Located, Hashable {
  /// The declaration name or binding pattern as it appears in the source.
  public let name: String

  /// The start of the declaration in the source file.
  public let location: DeclarationLocation
}

extension SourceExpression {
  /// The named declarations that contain the expression, starting with the
  /// nearest declaration.
  ///
  /// Includes local functions, bindings and accessors. For an expression read
  /// from a call argument, the list is limited to declarations inside that
  /// argument.
  public var enclosingDeclarations: [EnclosingDeclaration] {
    context.enclosingDeclarations(of: syntax)
  }
}
