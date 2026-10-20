import BylawsSyntax

final class StatementSpacingRewriter: SyntaxRewriter {
  override func visit(_ node: CodeBlockItemListSyntax)
    -> CodeBlockItemListSyntax
  {
    let rewritten = super.visit(node)
    guard isLocal(node) else { return rewritten }
    var items: [CodeBlockItemSyntax] = []
    for var item in rewritten {
      if let previous = items.last,
         needsBlankLine(between: previous, and: item)
      {
        let boundary = previous.trailingTrivia + item.leadingTrivia
        if !hasBlankLine(in: boundary), let newline = newline(in: boundary) {
          item.leadingTrivia = newline + item.leadingTrivia
        }
      }
      items.append(item)
    }
    return CodeBlockItemListSyntax(items)
  }

  private enum StatementKind {
    case binding, call, tryCall, other
  }

  private func kind(of item: CodeBlockItemSyntax) -> StatementKind {
    if item.item.is(VariableDeclSyntax.self) { return .binding }
    guard case var .expr(expression) = item.item else { return .other }
    var hasTry = false
    while true {
      if let awaited = expression.as(AwaitExprSyntax.self) {
        expression = awaited.expression
      } else if let tried = expression.as(TryExprSyntax.self) {
        hasTry = true
        expression = tried.expression
      } else {
        break
      }
    }
    guard expression.is(FunctionCallExprSyntax.self) else { return .other }
    return hasTry ? .tryCall : .call
  }

  private func needsBlankLine(
    between previous: CodeBlockItemSyntax, and next: CodeBlockItemSyntax
  ) -> Bool {
    switch (kind(of: previous), kind(of: next)) {
    case (.tryCall, _), (_, .tryCall), (.binding, .call), (.call, .binding):
      true
    default:
      false
    }
  }

  private func isLocal(_ node: CodeBlockItemListSyntax) -> Bool {
    var parent = node.parent
    while let ancestor = parent {
      if ancestor.is(CodeBlockSyntax.self) || ancestor
        .is(ClosureExprSyntax.self)
      {
        return true
      }
      parent = ancestor.parent
    }
    return false
  }

  private func hasBlankLine(in trivia: Trivia) -> Bool {
    var count = 0
    for piece in trivia {
      switch piece {
      case let .newlines(lines), let .carriageReturns(lines),
           let .carriageReturnLineFeeds(lines):
        count += lines
      case .spaces, .tabs:
        break
      default:
        count = 0
      }
      if count >= 2 { return true }
    }
    return false
  }

  private func newline(in trivia: Trivia) -> Trivia? {
    for piece in trivia {
      switch piece {
      case .newlines: return .newlines(1)
      case .carriageReturns: return .carriageReturns(1)
      case .carriageReturnLineFeeds: return .carriageReturnLineFeeds(1)
      default: continue
      }
    }
    return nil
  }
}
