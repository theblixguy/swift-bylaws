import BylawsSyntax

extension SourceLayoutReplacement {
  struct Item {
    let source: SourceSlice
    let node: Syntax
    let contentRange: Range<Int>

    init(
      source: SourceSlice, tree: SourceFileSyntax,
      validatesTrailingTrivia: Bool = true
    ) throws {
      self.source = source
      guard let token = tree
        .token(at: .init(utf8Offset: source.range.lowerBound))
      else {
        throw SourceLayoutReplacementError.unsupportedElement
      }
      var candidate: Syntax? = Syntax(token)
      var result: Syntax?
      while let syntax = candidate {
        let trimmedRange = syntax.positionAfterSkippingLeadingTrivia.utf8Offset
          ..< syntax.endPositionBeforeTrailingTrivia.utf8Offset
        if canonicalRange(of: syntax) == source.range || trimmedRange == source
          .range
        {
          if isList(syntax.parent) {
            result = syntax
            break
          }
          if let binding = syntax.as(PatternBindingSyntax.self),
             let variable = binding.parent?.parent?.as(VariableDeclSyntax.self),
             variable.bindings.count == 1
          {
            let declaration = Syntax(variable)
            result = isList(declaration.parent) ? declaration : declaration
              .parent
            break
          }
          if let parent = syntax.parent,
             parent.is(LabeledExprSyntax.self) || parent
               .is(ArrayElementSyntax.self),
             isList(parent.parent)
          {
            result = parent
            break
          }
          if let parent = syntax.parent,
             parent.is(MemberBlockItemSyntax.self) || parent
               .is(CodeBlockItemSyntax.self),
             isList(parent.parent)
          {
            result = parent
            break
          }
        }
        candidate = syntax.parent
      }
      guard let result, isList(result.parent) else {
        throw SourceLayoutReplacementError.unsupportedElement
      }
      if result.is(IfConfigDeclSyntax.self)
        || result.as(MemberBlockItemSyntax.self)?.decl
        .is(IfConfigDeclSyntax.self) == true
        || result.as(CodeBlockItemSyntax.self)?.item
        .is(IfConfigDeclSyntax.self) == true
      { throw SourceLayoutReplacementError.conditionalCompilation }
      guard !result.tokens(viewMode: .sourceAccurate).contains(where: { token in
        token.tokenKind == .poundSourceLocation
          || token.leadingTrivia.contains(where: \.isLayoutControl)
          || token.trailingTrivia.contains(where: \.isLayoutControl)
      }) else { throw SourceLayoutReplacementError.ambiguousTrivia }
      node = result
      let lower = try Self.contentStart(of: result)
      let upper = Self.contentEnd(of: result)
      contentRange = lower..<upper
      guard !validatesTrailingTrivia || result.trailingTrivia
        .allSatisfy(\.isLayoutWhitespace)
      else {
        throw SourceLayoutReplacementError.ambiguousTrivia
      }
      if result.as(CodeBlockItemSyntax.self)?.semicolon != nil
        || result.as(MemberBlockItemSyntax.self)?.semicolon != nil
      { throw SourceLayoutReplacementError.unsupportedElement }
    }

    private static func contentStart(of node: Syntax) throws -> Int {
      let trivia = Array(node.leadingTrivia)
      guard let first = trivia.firstIndex(where: { !$0.isLayoutWhitespace })
      else {
        return node.positionAfterSkippingLeadingTrivia.utf8Offset
      }
      guard node.position.utf8Offset == 0 || trivia[..<first]
        .contains(where: \.isLayoutNewline),
        trivia[first...]
          .allSatisfy({ $0.isLayoutWhitespace || $0.isLayoutComment })
      else { throw SourceLayoutReplacementError.ambiguousTrivia }
      if node.position.utf8Offset == 0,
         trivia
           .contains(where: { $0.isLayoutComment && !$0.isLayoutDocumentation })
      { throw SourceLayoutReplacementError.ambiguousTrivia }
      if let lastComment = trivia.lastIndex(where: \.isLayoutComment),
         trivia[(lastComment + 1)...]
           .reduce(0, { $0 + $1.layoutNewlineCount }) > 1
      { throw SourceLayoutReplacementError.ambiguousTrivia }
      return node.position.utf8Offset + trivia[..<first]
        .reduce(0) { $0 + $1.sourceLength.utf8Length }
    }

    static func contentEnd(of node: Syntax) -> Int {
      if let comma = node.as(LabeledExprSyntax.self)?.trailingComma
        ?? node.as(ArrayElementSyntax.self)?.trailingComma
        ?? node.as(DictionaryElementSyntax.self)?.trailingComma
        ?? node.as(EnumCaseElementSyntax.self)?.trailingComma
        ?? node.as(FunctionParameterSyntax.self)?.trailingComma
      { return comma.position.utf8Offset }
      return node.endPositionBeforeTrailingTrivia.utf8Offset
    }
  }

  struct List {
    let range: Range<Int>
    let leadingContentStart: Int
    let trailingContentEnd: Int
    let hasDeclarationBoundary: Bool
    let hasCommas: Bool
    let hasTrailingComma: Bool
    let isVertical: Bool
    let isDelimited: Bool
    let ownerStart: Int?
    let nextContentStart: Int?
    let closesOwner: Bool

    init(items: [Item], snapshot: SourceSnapshot) throws {
      let ordered = items.sorted { $0.node.position < $1.node.position }
      let first = ordered[0]
      let last = ordered[ordered.count - 1]
      guard let list = first.node.parent,
            items.allSatisfy({ $0.node.parent?.id == list.id })
      else {
        throw SourceLayoutReplacementError.noncontiguousElements
      }
      let siblings = Array(list.children(viewMode: .sourceAccurate))
      guard let start = siblings.firstIndex(where: { $0.id == first.node.id }),
            let end = siblings.firstIndex(where: { $0.id == last.node.id }),
            siblings[start...end].map(\.id) == ordered.map(\.node.id)
      else {
        throw SourceLayoutReplacementError.noncontiguousElements
      }
      let isAttributes = list.is(AttributeListSyntax.self)
      hasDeclarationBoundary = isAttributes || list
        .is(DeclModifierListSyntax.self)
      hasCommas = list.is(LabeledExprListSyntax.self)
        || list.is(ArrayElementListSyntax.self) || list
        .is(DictionaryElementListSyntax.self)
        || list.is(EnumCaseElementListSyntax.self) || list
        .is(FunctionParameterListSyntax.self)
      isVertical = list.is(MemberBlockItemListSyntax.self) || list
        .is(CodeBlockItemListSyntax.self)
      isDelimited = list.is(LabeledExprListSyntax.self)
        || list.is(ArrayElementListSyntax.self) || list
        .is(DictionaryElementListSyntax.self)
        || list.is(FunctionParameterListSyntax.self)
      hasTrailingComma = last.node.as(LabeledExprSyntax.self)?
        .trailingComma != nil
        || last.node.as(ArrayElementSyntax.self)?.trailingComma != nil
        || last.node.as(DictionaryElementSyntax.self)?.trailingComma != nil
        || last.node.as(EnumCaseElementSyntax.self)?.trailingComma != nil
        || last.node.as(FunctionParameterSyntax.self)?.trailingComma != nil
      if hasCommas || hasDeclarationBoundary {
        guard items.count == siblings.count else {
          throw SourceLayoutReplacementError.noncontiguousElements
        }
      }
      leadingContentStart = first.contentRange.lowerBound
      trailingContentEnd = last.node.endPositionBeforeTrailingTrivia.utf8Offset
      let next = last.node.lastToken(viewMode: .sourceAccurate)?
        .nextToken(viewMode: .sourceAccurate)
      nextContentStart = next?.positionAfterSkippingLeadingTrivia.utf8Offset
      closesOwner = next?.tokenKind == .rightBrace || next?
        .tokenKind == .rightParen
        || next?.tokenKind == .rightSquare
      let owner = list.parent
      ownerStart = if owner?.is(MemberBlockSyntax.self) == true
        || owner?.is(CodeBlockSyntax.self) == true
        || owner?.is(ClosureExprSyntax.self) == true
      { owner?.positionAfterSkippingLeadingTrivia.utf8Offset } else { nil }
      if hasDeclarationBoundary || isDelimited {
        guard next?.leadingTrivia.allSatisfy(\.isLayoutWhitespace) != false
        else {
          throw SourceLayoutReplacementError.ambiguousTrivia
        }
      }
      if isDelimited,
         let previous = first.node.firstToken(viewMode: .sourceAccurate)?
           .previousToken(viewMode: .sourceAccurate),
         !previous.trailingTrivia.allSatisfy(\.isLayoutWhitespace)
      { throw SourceLayoutReplacementError.ambiguousTrivia }
      let bytes = Array(snapshot.text.utf8)
      var lower = leadingContentStart
      while lower > 0, Self.isWhitespace(bytes[lower - 1]) { lower -= 1 }
      var upper = trailingContentEnd
      while upper < bytes.count, Self.isWhitespace(bytes[upper]) { upper += 1 }
      range = lower..<upper
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
      byte == 32 || byte == 9 || byte == 10 || byte == 13
    }
  }

  static func isList(_ node: Syntax?) -> Bool {
    guard let node else { return false }
    return node.is(AttributeListSyntax.self) || node
      .is(MemberBlockItemListSyntax.self)
      || node.is(CodeBlockItemListSyntax.self) || node
      .is(LabeledExprListSyntax.self)
      || node.is(ArrayElementListSyntax.self) || node
      .is(DictionaryElementListSyntax.self)
      || node.is(EnumCaseElementListSyntax.self) || node
      .is(DeclModifierListSyntax.self)
      || node.is(FunctionParameterListSyntax.self)
  }

  static func canonicalRange(of syntax: Syntax) -> Range<Int> {
    syntax.positionAfterSkippingLeadingTrivia.utf8Offset..<Item
      .contentEnd(of: syntax)
  }
}

extension TriviaPiece {
  fileprivate var isLayoutControl: Bool {
    let text: String
    switch self {
    case let .lineComment(value), let .blockComment(value),
         let .docLineComment(value), let .docBlockComment(value): text = value
    default: return false
    }
    let content = text.drop { $0 == "/" || $0 == "*" || $0.isWhitespace }
    return content.hasPrefix("swiftformat:") || content.hasPrefix("swiftlint:")
      || content.hasPrefix("bylaws:")
  }

  fileprivate var isLayoutDocumentation: Bool {
    switch self {
    case .docLineComment, .docBlockComment: true
    default: false
    }
  }

  fileprivate var isLayoutWhitespace: Bool {
    switch self {
    case .spaces, .tabs, .newlines, .carriageReturns,
         .carriageReturnLineFeeds: true
    default: false
    }
  }

  fileprivate var isLayoutNewline: Bool { layoutNewlineCount > 0 }

  fileprivate var layoutNewlineCount: Int {
    switch self {
    case let .newlines(count), let .carriageReturns(count),
         let .carriageReturnLineFeeds(count): count
    default: 0
    }
  }

  fileprivate var isLayoutComment: Bool {
    switch self {
    case .lineComment, .blockComment, .docLineComment, .docBlockComment: true
    default: false
    }
  }
}
