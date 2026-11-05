import BylawsSyntax

struct SourceListContext: Sendable {
  enum Kind: Sendable, Hashable, Codable {
    case arguments, attributes, modifiers, members, statements
  }

  let owner: SourceSlice
  let kind: Kind

  func resolve() throws -> SourceListSyntax {
    let syntax = try owner.syntaxNode()
    if let binding = syntax.as(PatternBindingSyntax.self),
       let declaration = binding.parent?.parent?.as(VariableDeclSyntax.self),
       declaration.bindings.count == 1
    {
      let declarationSource = try SourceSlice(
        snapshot: owner.snapshot,
        range: declaration.positionAfterSkippingLeadingTrivia.utf8Offset
          ..< declaration.endPositionBeforeTrailingTrivia.utf8Offset
      )
      return try SourceListContext(owner: declarationSource, kind: kind)
        .resolve()
    }
    switch kind {
    case .arguments:
      let arguments: LabeledExprListSyntax
      let left: TokenSyntax?
      let right: TokenSyntax?
      let calleeEnd: AbsolutePosition
      switch syntax.as(SyntaxEnum.self) {
      case let .functionCallExpr(call):
        (arguments, left, right) = (
          call.arguments,
          call.leftParen,
          call.rightParen
        )
        calleeEnd = call.calledExpression.endPositionBeforeTrailingTrivia
      case let .macroExpansionExpr(call):
        (arguments, left, right) = (
          call.arguments,
          call.leftParen,
          call.rightParen
        )
        calleeEnd = call.genericArgumentClause?.endPositionBeforeTrailingTrivia
          ?? call.macroName.endPositionBeforeTrailingTrivia
      case let .macroExpansionDecl(call):
        (arguments, left, right) = (
          call.arguments,
          call.leftParen,
          call.rightParen
        )
        calleeEnd = call.genericArgumentClause?.endPositionBeforeTrailingTrivia
          ?? call.macroName.endPositionBeforeTrailingTrivia
      default: throw SourceError.missingPart
      }
      if left == nil, right == nil, arguments.isEmpty {
        return try SourceListSyntax(
          context: self, syntax: Syntax(arguments),
          bounds: calleeEnd.utf8Offset..<calleeEnd.utf8Offset,
          addsParentheses: true
        )
      }
      guard let left, let right else { throw SourceError.missingPart }
      return try make(Syntax(arguments), between: left, and: right)
    case .attributes, .modifiers:
      let expected: SyntaxKind = kind == .attributes ? .attributeList :
        .declModifierList
      guard let list = syntax.children(viewMode: .all)
        .first(where: { $0.kind == expected }),
        let next = syntax.tokens(viewMode: .sourceAccurate).first(where: {
          $0.positionAfterSkippingLeadingTrivia >= list
            .endPositionBeforeTrailingTrivia
        })
      else { throw SourceError.missingPart }
      var lower = list.firstToken(viewMode: .sourceAccurate)?
        .positionAfterSkippingLeadingTrivia.utf8Offset
        ?? next.positionAfterSkippingLeadingTrivia.utf8Offset
      if !list.children(viewMode: .sourceAccurate).isEmpty {
        let bytes = owner.snapshot.syntaxContext?
          .bytes ?? Array(owner.snapshot.text.utf8)
        while lower > 0,
              [UInt8(9), 10, 13, 32].contains(bytes[lower - 1]) { lower -= 1 }
      }
      return try SourceListSyntax(
        context: self, syntax: list,
        bounds: lower..<next.positionAfterSkippingLeadingTrivia.utf8Offset
      )
    case .members:
      guard let block = syntax.children(viewMode: .sourceAccurate)
        .compactMap({ $0.as(MemberBlockSyntax.self) }).first
      else { throw SourceError.missingPart }
      return try make(
        Syntax(block.members),
        between: block.leftBrace,
        and: block.rightBrace
      )
    case .statements:
      if let block = syntax.as(CodeBlockSyntax.self) {
        return try make(
          Syntax(block.statements),
          between: block.leftBrace,
          and: block.rightBrace
        )
      }
      if let closure = syntax.as(ClosureExprSyntax.self) {
        return try make(
          Syntax(closure.statements),
          between: closure.signature?.inKeyword ?? closure.leftBrace,
          and: closure.rightBrace
        )
      }
      if let file = syntax.as(SourceFileSyntax.self) {
        return try SourceListSyntax(
          context: self, syntax: Syntax(file.statements), bounds: owner.range
        )
      }
      throw SourceError.missingPart
    }
  }

  private func make(
    _ syntax: Syntax, between left: TokenSyntax, and right: TokenSyntax
  ) throws -> SourceListSyntax {
    try SourceListSyntax(
      context: self, syntax: syntax,
      bounds: left.endPositionBeforeTrailingTrivia.utf8Offset
        ..< right.positionAfterSkippingLeadingTrivia.utf8Offset
    )
  }
}

struct SourceListSyntax {
  let context: SourceListContext
  let syntax: Syntax
  let source: SourceSlice
  let elements: [Syntax]
  let addsParentheses: Bool

  init(
    context: SourceListContext, syntax: Syntax, bounds: Range<Int>,
    addsParentheses: Bool = false
  ) throws {
    self.context = context
    self.syntax = syntax
    source = try SourceSlice(snapshot: context.owner.snapshot, range: bounds)
    elements = Array(syntax.children(viewMode: .sourceAccurate))
    self.addsParentheses = addsParentheses
  }

  var hasCommas: Bool { context.kind == .arguments }

  var isVertical: Bool {
    context.kind == .members || context.kind == .statements
      || source.text.contains(where: \.isNewline)
  }

  func slices() throws -> [SourceSlice] {
    try elements.map {
      try SourceSlice(
        snapshot: source.snapshot,
        range: $0.positionAfterSkippingLeadingTrivia.utf8Offset
          ..< $0.endPositionBeforeTrailingTrivia.utf8Offset
      )
    }
  }

  func index(of source: SourceSlice) throws -> Int {
    guard self.source.snapshot == source.snapshot else {
      throw SourceError.differentSnapshots
    }
    let item = try SourceLayoutReplacement.Item(
      source: source, tree: self.source.snapshot.syntaxTree(),
      validatesTrailingTrivia: false
    )
    guard let index = elements.firstIndex(where: { $0.id == item.node.id })
    else {
      throw SourceError.syntaxMismatch
    }
    return index
  }
}
