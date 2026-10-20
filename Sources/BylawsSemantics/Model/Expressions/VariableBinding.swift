import BylawsSyntax

/// A variable declaration or optional binding, including local bindings.
public struct VariableBinding: Declaration {
  private let originalSource: SourceSlice?
  private let originalName: SourceSlice?
  /// The binding pattern, such as `token` or `(key, value)`.
  public let name: String

  /// The initial value, or `nil` when the binding has no initialiser.
  public let initialValue: SourceExpression?

  /// Whether the binding uses `var`.
  public let isMutable: Bool

  /// The start of the binding pattern.
  public let location: DeclarationLocation

  /// The named declarations that contain the binding, starting with the nearest
  /// declaration.
  public let enclosingDeclarations: [EnclosingDeclaration]

  /// The conditional-compilation branches that contain the binding,
  /// starting with the outermost branch.
  public let compilationBranches: [CompilationBranch]

  init(
    pattern: PatternSyntax, initialValue: ExprSyntax?, isMutable: Bool,
    syntax: some SyntaxProtocol, source: SourceText, origin: DeclarationLocation
  ) {
    let context = SourceContext(source: source, origin: origin)
    originalSource = try? context.sourceSlice(of: syntax)
    originalName = try? context.sourceSlice(of: pattern)
    name = source.trimmedText(of: pattern)
    self.initialValue = initialValue.map {
      SourceExpression($0, source: source, origin: origin)
    }
    self.isMutable = isMutable
    location = context.location(at: pattern.positionAfterSkippingLeadingTrivia)
    enclosingDeclarations = context.enclosingDeclarations(of: syntax)
    compilationBranches = context.compilationBranches(of: syntax)
  }

  /// The binding's source, excluding outer trivia.
  public var source: SourceSlice {
    get throws { try originalSource.required() }
  }

  /// The binding pattern's source, excluding outer trivia.
  public var nameSource: SourceSlice {
    get throws { try originalName.required() }
  }
}
