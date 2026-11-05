import BylawsSyntax

extension SourceNode {
  /// The conditional represented by this node or its expression statement.
  public var ifExpression: SourceIfExpression? {
    let expression = syntax.as(IfExprSyntax.self)
      ?? syntax.as(ExpressionStmtSyntax.self)?.expression.as(IfExprSyntax.self)
    return expression.map { SourceIfExpression(syntax: $0, context: context) }
  }
}

/// An if expression and its branches from captured source.
public struct SourceIfExpression: SourceProviding, Located, Summarised,
  Sendable,
  Equatable
{
  let syntax: IfExprSyntax
  let context: SourceContext

  /// The conditional's start in the source file.
  public var location: DeclarationLocation {
    context.location(at: syntax.positionAfterSkippingLeadingTrivia)
  }

  /// The conditional's source text.
  public var summary: String { context.source.trimmedText(of: syntax) }

  /// The block executed when the conditions succeed.
  public var body: SourceNode {
    SourceNode(Syntax(syntax.body), context: context, kind: .codeBlock)
  }

  /// The alternative block or conditional, or `nil` without an else branch.
  public var elseBody: SourceNode? {
    syntax.elseBody.map { body in
      let node = Syntax(body)
      return SourceNode(
        node, context: context,
        kind: node.is(CodeBlockSyntax.self) ? .codeBlock : .ifExpression
      )
    }
  }

  /// The complete conditional, excluding its outer trivia.
  public var source: SourceSlice {
    get throws { try context.sourceSlice(of: syntax) }
  }

  /// Compares the conditional's source text and location.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.location == rhs.location && lhs.summary == rhs.summary
  }
}
