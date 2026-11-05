import BylawsSyntax

extension SourceReplacementPlan {
  static func preservingGrouping(_ content: Node, target: SourceSlice)
    throws -> Node
  {
    let targetNode = try target.syntaxNode()
    var node = content
    let ranges = node.ranges
    guard !ranges.isEmpty
    else { throw SourceReplacementError.unsupportedSyntax }
    if targetNode.is(ExprSyntax.self), !Self.isStatement(targetNode),
       ranges.count == 1,
       !Self.containsScope(node)
    {
      let retained = try SourceSlice(
        snapshot: target.snapshot,
        range: ranges[0]
      )
      .syntaxNode()
      if retained.is(ExprSyntax.self), Self.needsParentheses(retained) {
        node = .parentheses(node)
      }
    } else if targetNode.is(TypeSyntax.self), ranges.count == 1 {
      let retained = try SourceSlice(
        snapshot: target.snapshot,
        range: ranges[0]
      )
      .syntaxNode()
      if !retained.is(IdentifierTypeSyntax.self),
         !retained.is(MemberTypeSyntax.self),
         targetNode.parent?.is(TypeInitializerClauseSyntax.self) != true,
         targetNode.parent?.is(TypeAnnotationSyntax.self) != true
      {
        node = .parentheses(node)
      }
    }
    return node
  }

  func needsParentheses(afterReplacingWith text: String, target: SourceSlice)
    throws -> Bool
  {
    let syntax = try target.syntaxNode()
    let retained = try parseReplacement(text, target: target)
    if syntax.is(ExprSyntax.self), !Self.isStatement(syntax) {
      return Self.needsParentheses(retained)
    }
    if syntax.is(TypeSyntax.self) {
      return !retained.is(IdentifierTypeSyntax.self)
        && !retained.is(MemberTypeSyntax.self)
        && !retained.is(TupleTypeSyntax.self)
        && syntax.parent?.is(TypeInitializerClauseSyntax.self) != true
        && syntax.parent?.is(TypeAnnotationSyntax.self) != true
    }
    return false
  }

  private func parseReplacement(
    _ text: String,
    target: SourceSlice
  ) throws -> Syntax {
    let syntax = try target.syntaxNode()
    let mode = target.snapshot.swiftLanguageMode
    let parsed: Syntax
    if syntax.is(TypeSyntax.self) {
      parsed = Syntax(mode.parse(text, as: TypeSyntax.self))
    } else if Self.isStatement(syntax) || syntax.is(StmtSyntax.self) {
      parsed = Syntax(mode.parse(text, as: CodeBlockItemListSyntax.self))
    } else if syntax.is(ExprSyntax.self) {
      parsed = Syntax(mode.parse(text, as: ExprSyntax.self))
    } else if syntax.is(DeclSyntax.self) {
      parsed = if syntax.parent?.is(MemberBlockItemSyntax.self) == true {
        Syntax(mode.parse(text, as: MemberBlockItemListSyntax.self))
      } else {
        Syntax(mode.parse(text, as: CodeBlockItemListSyntax.self))
      }
    } else if syntax.is(CodeBlockSyntax.self) {
      if let owner = syntax.parent?.as(IfExprSyntax.self),
         owner.elseBody?.id == syntax.id
      {
        let expression = mode.parse(text, as: ExprSyntax.self)
        parsed = if expression.is(IfExprSyntax.self), !expression.hasError {
          Syntax(expression)
        } else {
          Syntax(mode.parse(text, as: CodeBlockSyntax.self))
        }
      } else {
        parsed = Syntax(mode.parse(text, as: CodeBlockSyntax.self))
      }
    } else {
      throw SourceReplacementError.unsupportedSyntax
    }
    guard !parsed.hasError else { throw SourceReplacementError.syntaxChanged }
    return parsed
  }

  static func isStatement(_ node: Syntax) -> Bool {
    node.parent?.is(ExpressionStmtSyntax.self) == true
      || node.parent?.is(CodeBlockItemSyntax.self) == true
  }

  private static func needsParentheses(_ syntax: Syntax) -> Bool {
    if needsPostfixGrouping(syntax) { return true }
    return switch syntax.kind {
    case .declReferenceExpr, .memberAccessExpr, .functionCallExpr,
         .subscriptCallExpr, .integerLiteralExpr, .floatLiteralExpr,
         .booleanLiteralExpr, .nilLiteralExpr, .stringLiteralExpr,
         .arrayExpr, .dictionaryExpr, .tupleExpr: false
    default: true
    }
  }

  private static func needsPostfixGrouping(_ syntax: Syntax) -> Bool {
    switch syntax.as(SyntaxEnum.self) {
    case .optionalChainingExpr: true
    case let .forceUnwrapExpr(node): needsPostfixGrouping(Syntax(node
          .expression))
    case let .genericSpecializationExpr(node): needsPostfixGrouping(Syntax(node
          .expression))
    case let .memberAccessExpr(node): node.base
      .map { needsPostfixGrouping(Syntax($0)) } == true
    case let .functionCallExpr(node):
      node.trailingClosure != nil || !node.additionalTrailingClosures.isEmpty
        || needsPostfixGrouping(Syntax(node.calledExpression))
    case let .subscriptCallExpr(node): needsPostfixGrouping(Syntax(node
          .calledExpression))
    default: false
    }
  }
}
