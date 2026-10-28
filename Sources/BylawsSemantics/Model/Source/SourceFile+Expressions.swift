import BylawsSyntax

extension SourceFile {
  /// The expressions in the file, including those in local declarations and
  /// closures.
  ///
  /// The query covers every `#if` branch and lists each expression before
  /// the expressions inside it.
  /// - Complexity: O(n), where n is the length of the source file.
  public var expressions: [SourceExpression] {
    let source = SourceText(
      buffer: sourceBuffer,
      swiftLanguageMode: swiftLanguageMode
    )
    let collector = ExpressionCollector(source: source, path: path)
    collector.walk(syntaxTree())
    return collector.expressions
  }
}

private final class ExpressionCollector: SyntaxAnyVisitor {
  private let source: SourceText
  private let origin: DeclarationLocation
  private(set) var expressions: [SourceExpression] = []

  init(source: SourceText, path: String) {
    self.source = source
    origin = .start(of: path)
    super.init(viewMode: .sourceAccurate)
  }

  override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
    if let member = node.parent?.as(MemberAccessExprSyntax.self),
       Syntax(member.declName) == node
    {
      return .skipChildren
    }
    if let expression = node.as(ExprSyntax.self) {
      expressions.append(SourceExpression(
        expression,
        source: source,
        origin: origin
      ))
    }
    return .visitChildren
  }
}
