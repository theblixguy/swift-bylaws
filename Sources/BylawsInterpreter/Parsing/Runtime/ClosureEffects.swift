import SwiftSyntax

final class ClosureEffects: SyntaxVisitor {
  private(set) var usesAwait = false
  private(set) var usesTry = false

  override func visit(_ node: ClosureExprSyntax)
    -> SyntaxVisitorContinueKind { .skipChildren }

  override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
    if token.tokenKind == .keyword(.await) { usesAwait = true }
    if token.tokenKind == .keyword(.try) { usesTry = true }
    return .visitChildren
  }
}
