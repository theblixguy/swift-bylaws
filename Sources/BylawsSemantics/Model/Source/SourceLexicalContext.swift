import BylawsSyntax

final class SourceLexicalContext: Sendable {
  struct Token: Sendable {
    let kind: SourceToken.Kind
    let source: SourceSlice
    let leadingTrivia: [SourceTrivia]
    let trailingTrivia: [SourceTrivia]
  }

  let tokens: [Token]
  let trivia: [SourceTrivia]

  init(snapshot: SourceSnapshot) throws {
    let tree = snapshot.syntaxTree()
    var tokens: [Token] = []
    var trivia: [SourceTrivia] = []
    for token in tree.tokens(viewMode: .sourceAccurate) {
      let leading = try Self.trivia(
        token.leadingTrivia, at: token.position.utf8Offset, snapshot: snapshot
      )
      let trailing = try Self.trivia(
        token.trailingTrivia,
        at: token.endPositionBeforeTrailingTrivia.utf8Offset,
        snapshot: snapshot
      )
      trivia.append(contentsOf: leading)
      trivia.append(contentsOf: trailing)
      guard token.presence == .present, token.tokenKind != .endOfFile else {
        continue
      }
      let range = token.positionAfterSkippingLeadingTrivia.utf8Offset
        ..< token.endPositionBeforeTrailingTrivia.utf8Offset
      guard !range.isEmpty else { continue }
      tokens.append(Token(
        kind: SourceToken.Kind(token.tokenKind),
        source: try SourceSlice(snapshot: snapshot, range: range),
        leadingTrivia: leading, trailingTrivia: trailing
      ))
    }
    self.tokens = tokens
    self.trivia = trivia
  }

  private static func trivia(
    _ trivia: Trivia, at start: Int, snapshot: SourceSnapshot
  ) throws -> [SourceTrivia] {
    var offset = start
    return try trivia.compactMap { piece in
      let end = offset + piece.sourceLength.utf8Length
      defer { offset = end }
      guard end > offset else { return nil }
      return SourceTrivia(
        kind: SourceTrivia.Kind(piece),
        source: try SourceSlice(snapshot: snapshot, range: offset..<end)
      )
    }
  }
}
