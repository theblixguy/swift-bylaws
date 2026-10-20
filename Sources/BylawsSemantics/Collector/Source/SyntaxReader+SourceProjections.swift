import BylawsSyntax

extension SyntaxReader {
  func macroSource(of node: some SyntaxProtocol) -> ParsedSource? {
    let name: TokenSyntax
    let pound: TokenSyntax
    if let macro = node.as(MacroExpansionExprSyntax.self) {
      name = macro.macroName
      pound = macro.pound
    } else if let macro = node.as(MacroExpansionDeclSyntax.self) {
      name = macro.macroName
      pound = macro.pound
    } else { return nil }
    guard var result = parsedSource(of: node, name: name) else { return nil }
    result.memberName = result.name
    result.calledExpression = try? SourceSlice(
      snapshot: text.buffer.snapshot.required(),
      range: pound.positionAfterSkippingLeadingTrivia.utf8Offset
        ..< name.endPositionBeforeTrailingTrivia.utf8Offset
    )
    result.name = result.calledExpression
    return result
  }

  func callSource(of node: FunctionCallExprSyntax) -> ParsedSource? {
    guard var result = parsedSource(of: node) else { return nil }
    result.calledExpression = try? sourceSlice(of: node.calledExpression)
    result.memberName = referenceName(in: node.calledExpression).flatMap {
      try? sourceSlice(of: $0)
    }
    result.name = result.calledExpression
    return result
  }

  private func referenceName(in expression: ExprSyntax) -> TokenSyntax? {
    if let reference = expression.as(DeclReferenceExprSyntax.self) {
      return reference.baseName
    }
    if let member = expression.as(MemberAccessExprSyntax.self) {
      return member.declName.baseName
    }
    if let generic = expression.as(GenericSpecializationExprSyntax.self) {
      return referenceName(in: generic.expression)
    }
    if let chained = expression.as(OptionalChainingExprSyntax.self) {
      return referenceName(in: chained.expression)
    }
    if let unwrapped = expression.as(ForceUnwrapExprSyntax.self) {
      return referenceName(in: unwrapped.expression)
    }
    return nil
  }

  func parsedSource(
    of node: some SyntaxProtocol,
    name: (any SyntaxProtocol)? = nil,
    body: (any SyntaxProtocol)? = nil
  ) -> ParsedSource? {
    guard let whole = try? sourceSlice(of: node) else { return nil }
    return ParsedSource(
      whole: whole,
      name: name.flatMap { try? sourceSlice(of: $0) },
      body: body.flatMap { try? bodySlice(of: $0) }
    )
  }

  private func bodySlice(of node: some SyntaxProtocol) throws -> SourceSlice {
    let left: TokenSyntax
    let right: TokenSyntax
    if let block = node.as(CodeBlockSyntax.self) {
      left = block.leftBrace
      right = block.rightBrace
    } else if let block = node.as(MemberBlockSyntax.self) {
      left = block.leftBrace
      right = block.rightBrace
    } else if let block = node.as(AccessorBlockSyntax.self) {
      left = block.leftBrace
      right = block.rightBrace
    } else { throw SourceError.missingPart }
    return try SourceSlice(
      snapshot: text.buffer.snapshot.required(),
      range: left.endPositionBeforeTrailingTrivia.utf8Offset
        ..< right.positionAfterSkippingLeadingTrivia.utf8Offset
    )
  }

  func sourceSlice(of node: some SyntaxProtocol) throws -> SourceSlice {
    try SourceSlice(
      snapshot: text.buffer.snapshot.required(),
      range: text.trimmedRange(of: node)
    )
  }
}
