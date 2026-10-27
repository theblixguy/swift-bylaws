import BylawsSyntax

extension ParsedSource {
  package var name: SourceSlice? { get throws { try part(.name) } }
  package var body: SourceSlice? { get throws { try part(.body) } }
  package var calledExpression: SourceSlice? {
    get throws { try part(.calledExpression) }
  }

  package var memberName: SourceSlice? {
    get throws { try part(.memberName) }
  }

  package var label: SourceSlice? { get throws { try part(.label) } }

  private enum Part { case name, body, calledExpression, memberName, label }

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
        case .name:
          if let name = name(in: node) {
            return try slice(of: name, in: snapshot)
          }
        case .body:
          if let body = body(in: node) {
            return try SourceSlice(
              snapshot: snapshot,
              range: body.opening.endPositionBeforeTrailingTrivia.utf8Offset
                ..< body.closing.positionAfterSkippingLeadingTrivia.utf8Offset
            )
          }
        case .calledExpression, .memberName:
          if let call = node.as(FunctionCallExprSyntax.self) {
            let expression: Syntax? = if part == .calledExpression {
              Syntax(call.calledExpression)
            } else { referenceName(in: call.calledExpression).map(Syntax.init) }
            return try expression.map { try slice(of: $0, in: snapshot) }
          }
          if let macro = macroName(in: node) {
            return try part == .memberName
              ? slice(of: macro.name, in: snapshot)
              : SourceSlice(
                snapshot: snapshot,
                range: macro.pound.positionAfterSkippingLeadingTrivia.utf8Offset
                  ..< macro.name.endPositionBeforeTrailingTrivia.utf8Offset
              )
          }
        case .label: break
        }
      }
      candidate = node.parent
    }
    return nil
  }

  private func name(in node: Syntax) -> Syntax? {
    switch node.as(SyntaxEnum.self) {
    case let .functionDecl(value): Syntax(value.name)
    case let .initializerDecl(value): Syntax(value.initKeyword)
    case let .classDecl(value): Syntax(value.name)
    case let .actorDecl(value): Syntax(value.name)
    case let .structDecl(value): Syntax(value.name)
    case let .enumDecl(value): Syntax(value.name)
    case let .protocolDecl(value): Syntax(value.name)
    case let .extensionDecl(value): Syntax(value.extendedType)
    case let .typeAliasDecl(value): Syntax(value.name)
    case let .importDecl(value): Syntax(value.path)
    case let .enumCaseElement(value): Syntax(value.name)
    case let .patternBinding(value): Syntax(value.pattern)
    case let .optionalBindingCondition(value): Syntax(value.pattern)
    case let .functionCallExpr(value): Syntax(value.calledExpression)
    default: nil
    }
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

  private func macroName(in node: Syntax)
    -> (pound: TokenSyntax, name: TokenSyntax)?
  {
    if let macro = node.as(MacroExpansionExprSyntax.self) {
      return (macro.pound, macro.macroName)
    }
    if let macro = node.as(MacroExpansionDeclSyntax.self) {
      return (macro.pound, macro.macroName)
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
