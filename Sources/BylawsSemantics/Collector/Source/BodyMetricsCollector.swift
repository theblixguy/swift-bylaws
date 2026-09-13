import SwiftSyntax

final class BodyMetricsCollector: LexicalRegionVisitor {
  private(set) var awaitCount = 0
  private var rawCyclomaticComplexity = 0

  var cyclomaticComplexity: Int {
    max(0, rawCyclomaticComplexity)
  }

  init() {
    super.init()
  }

  override func visit(_ node: AwaitExprSyntax) -> SyntaxVisitorContinueKind {
    awaitCount += 1
    return .visitChildren
  }

  override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
    rawCyclomaticComplexity += 1
    return .visitChildren
  }

  override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
    rawCyclomaticComplexity += 1
    return .visitChildren
  }

  override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
    rawCyclomaticComplexity += 1
    return .visitChildren
  }

  override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
    rawCyclomaticComplexity += 1
    return .visitChildren
  }

  override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
    rawCyclomaticComplexity += 1
    return .visitChildren
  }

  override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
    rawCyclomaticComplexity += 1
    return .visitChildren
  }

  override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
    rawCyclomaticComplexity += 1
    return .visitChildren
  }

  override func visit(_ node: FallThroughStmtSyntax)
    -> SyntaxVisitorContinueKind
  {
    rawCyclomaticComplexity -= 1
    return .visitChildren
  }
}
