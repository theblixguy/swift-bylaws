import BylawsSyntax

extension ParsedSource {
  package var body: SourceSlice? { get throws { try part(.body) } }

  package var memberName: SourceSlice? {
    get throws { try part(.memberName) }
  }

  package var label: SourceSlice? { get throws { try part(.label) } }

  private enum Part { case body, memberName, label }

  private func part(_ part: Part) throws -> SourceSlice? {
    let snapshot = try buffer.snapshot.required()
    var candidate = snapshot.token(at: range.lowerBound)
      .map(Syntax.init)
    while let node = candidate {
      if part == .label, let argument = node.as(LabeledExprSyntax.self),
         trimmedRange(of: argument.expression) == range
      {
        return try argument.label.map { try slice(of: $0, in: snapshot) }
      }
      if trimmedRange(of: node) == range {
        switch part {
        case .body:
          if let body = body(in: node) {
            return try SourceSlice(
              snapshot: snapshot,
              range: body.opening.endPositionBeforeTrailingTrivia.utf8Offset
                ..< body.closing.positionAfterSkippingLeadingTrivia.utf8Offset
            )
          }
        case .memberName:
          if let call = node.as(FunctionCallExprSyntax.self) {
            return try referenceName(in: call.calledExpression).map {
              try slice(of: $0, in: snapshot)
            }
          }
          if let macro = macroName(in: node) {
            return try slice(of: macro, in: snapshot)
          }
        case .label: break
        }
      }
      candidate = node.parent
    }
    return nil
  }

  private func body(in node: Syntax)
    -> (opening: TokenSyntax, closing: TokenSyntax)?
  {
    switch node.as(SyntaxEnum.self) {
    case let .functionDecl(value): value.body
      .map { ($0.leftBrace, $0.rightBrace) }
    case let .initializerDecl(value): value.body.map { (
        $0.leftBrace,
        $0.rightBrace
      ) }
    case let .classDecl(value): (
        value.memberBlock.leftBrace,
        value.memberBlock.rightBrace
      )
    case let .actorDecl(value): (
        value.memberBlock.leftBrace,
        value.memberBlock.rightBrace
      )
    case let .structDecl(value): (
        value.memberBlock.leftBrace,
        value.memberBlock.rightBrace
      )
    case let .enumDecl(value): (
        value.memberBlock.leftBrace,
        value.memberBlock.rightBrace
      )
    case let .protocolDecl(value): (
        value.memberBlock.leftBrace,
        value.memberBlock.rightBrace
      )
    case let .extensionDecl(value): (
        value.memberBlock.leftBrace,
        value.memberBlock.rightBrace
      )
    case let .patternBinding(value): value.accessorBlock.map { (
        $0.leftBrace,
        $0.rightBrace
      ) }
    default: nil
    }
  }

  private func macroName(in node: Syntax) -> TokenSyntax? {
    if let macro = node.as(MacroExpansionExprSyntax.self) {
      return macro.macroName
    }
    if let macro = node.as(MacroExpansionDeclSyntax.self) {
      return macro.macroName
    }
    return nil
  }

  private func referenceName(in expression: ExprSyntax) -> TokenSyntax? {
    switch Syntax(expression).as(SyntaxEnum.self) {
    case let .declReferenceExpr(value): value.baseName
    case let .memberAccessExpr(value): value.declName.baseName
    case let .genericSpecializationExpr(value): referenceName(in: value
        .expression)
    case let .optionalChainingExpr(value): referenceName(in: value.expression)
    case let .forceUnwrapExpr(value): referenceName(in: value.expression)
    default: nil
    }
  }

  private func slice(
    of node: some SyntaxProtocol,
    in snapshot: SourceSnapshot
  ) throws -> SourceSlice {
    try SourceSlice(snapshot: snapshot, range: trimmedRange(of: node))
  }

  private func trimmedRange(of node: some SyntaxProtocol) -> Range<Int> {
    node.positionAfterSkippingLeadingTrivia.utf8Offset
      ..< node.endPositionBeforeTrailingTrivia.utf8Offset
  }
}
