import BylawsSyntax

package struct SourceReplacementPlan: Sendable, Hashable, Codable {
  package indirect enum Node: Sendable, Hashable, Codable {
    case source(Range<Int>)
    case sequence([Node])
    case scope(Node)
    case parentheses(Node)

    var ranges: [Range<Int>] {
      switch self {
      case let .source(range): [range]
      case let .sequence(children): children.flatMap(\.ranges)
      case let .scope(content), let .parentheses(content): content.ranges
      }
    }
  }

  package let node: Node

  init(_ replacement: SourceReplacement, target: SourceSlice) throws {
    node = try Self.preservingGrouping(
      Self.capture(replacement.content, target: target), target: target
    )
    try validate(target: target)
  }

  func validate(target: SourceSlice) throws {
    guard try node == Self.preservingGrouping(
      Self.removingParentheses(node),
      target: target
    ) else {
      throw SourceReplacementError.syntaxChanged
    }
    let targetNode = try target.syntaxNode()
    let ranges = node.ranges.sorted { $0.lowerBound < $1.lowerBound }
    guard !ranges.isEmpty
    else { throw SourceReplacementError.unsupportedSyntax }
    if targetNode.is(TypeSyntax.self)
      || targetNode.is(ExprSyntax.self) && !Self.isStatement(targetNode)
    {
      guard ranges.count == 1, !Self.containsScope(node) else {
        throw SourceReplacementError.unsupportedSyntax
      }
      let retained = try SourceSlice(
        snapshot: target.snapshot,
        range: ranges[0]
      ).syntaxNode()
      guard targetNode.is(TypeSyntax.self)
        ? retained.is(TypeSyntax.self) : retained.is(ExprSyntax.self)
      else {
        throw SourceReplacementError.unsupportedSyntax
      }
    }
    var previous: Range<Int>?
    for range in ranges {
      guard SourceLayoutComposition.contains(target.range, range),
            previous.map({ $0.upperBound <= range.lowerBound }) ?? true
      else { throw SourceError.overlappingEdits }
      let retained = try SourceSlice(snapshot: target.snapshot, range: range)
      let syntax = try retained.syntaxNode()
      guard syntax.is(ExprSyntax.self) || syntax.is(StmtSyntax.self)
        || syntax.is(DeclSyntax.self) || syntax.is(TypeSyntax.self)
        || syntax.is(CodeBlockSyntax.self)
      else { throw SourceReplacementError.unsupportedSyntax }
      previous = range
    }
    for token in targetNode.tokens(viewMode: .sourceAccurate) {
      if token.tokenKind == .poundSourceLocation {
        throw SourceReplacementError.discardedTrivia
      }
      try Self.validate(
        token.leadingTrivia, from: token.position.utf8Offset,
        target: target.range, retained: ranges
      )
      try Self.validate(
        token.trailingTrivia,
        from: token.endPositionBeforeTrailingTrivia.utf8Offset,
        target: target.range, retained: ranges
      )
      if token.tokenKind == .multilineStringQuote {
        throw SourceReplacementError.multilineLiteral
      }
    }
  }

  private static func removingParentheses(_ node: Node) -> Node {
    switch node {
    case .source: node
    case let .sequence(children): .sequence(children.map(removingParentheses))
    case let .scope(content): .scope(removingParentheses(content))
    case let .parentheses(content): removingParentheses(content)
    }
  }

  private static func capture(
    _ content: SourceReplacement.Content, target: SourceSlice
  ) throws -> Node {
    switch content {
    case let .source(provider):
      let source = try provider.source
      guard source.snapshot == target.snapshot else {
        throw SourceError.differentSnapshots
      }
      guard SourceLayoutComposition.contains(target.range, source.range) else {
        throw SourceError.rangeOutOfBounds
      }
      return .source(source.range)
    case let .sequence(children):
      return try .sequence(children.map { try capture($0, target: target) })
    case let .scope(content):
      return try .scope(capture(content, target: target))
    }
  }

  static func containsScope(_ node: Node) -> Bool {
    switch node {
    case .scope: true
    case let .sequence(children): children.contains(where: containsScope)
    case let .parentheses(child): containsScope(child)
    case .source: false
    }
  }

  private static func validate(
    _ trivia: Trivia, from start: Int, target: Range<Int>,
    retained: [Range<Int>]
  ) throws {
    var offset = start
    for piece in trivia {
      let range = offset..<(offset + piece.sourceLength.utf8Length)
      offset = range.upperBound
      guard range.overlaps(target) else { continue }
      switch piece {
      case let .lineComment(text), let .blockComment(text),
           let .docLineComment(text), let .docBlockComment(text):
        let content = text.drop { $0 == "/" || $0 == "*" || $0.isWhitespace }
        guard !content.hasPrefix("swiftformat:"),
              !content.hasPrefix("swiftlint:"), !content.hasPrefix("bylaws:"),
              retained.contains(where: { SourceLayoutComposition.contains(
                $0,
                range
              ) })
        else { throw SourceReplacementError.discardedTrivia }
      case .spaces, .tabs, .newlines, .carriageReturns,
           .carriageReturnLineFeeds:
        break
      default: throw SourceReplacementError.discardedTrivia
      }
    }
  }
}
