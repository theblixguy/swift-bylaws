import BylawsSyntax

extension SourceProviding {
  /// The complete lexical tokens contained in the captured source.
  ///
  /// Tokens exclude trivia, parser-inserted tokens and the end-of-file marker.
  /// A slice that covers only part of a token omits that token. Neighbour
  /// projections retain the original file's context beyond the queried slice.
  /// - Complexity: O(n), where n is the length of the source file.
  public var tokens: [SourceToken] {
    get throws {
      let source = try source
      let context = try SourceLexicalContext(snapshot: source.snapshot)
      return context.tokens.indices.compactMap { index in
        let token = context.tokens[index]
        return source.contains(token.source)
          ? SourceToken(context: context, index: index) : nil
      }
    }
  }

  /// The complete trivia pieces contained in the captured source, in source order.
  ///
  /// This includes comments at the end of a file, including a comment-only file.
  /// A slice that covers part of a trivia piece omits that piece. String and
  /// regex contents retain their lexical categories rather than becoming comments.
  /// - Complexity: O(n), where n is the length of the source file.
  public var trivia: [SourceTrivia] {
    get throws {
      let source = try source
      return try SourceLexicalContext(snapshot: source.snapshot).trivia
        .filter { source.contains($0.source) }
    }
  }
}

extension SourceSlice {
  fileprivate func contains(_ other: SourceSlice) -> Bool {
    range.lowerBound <= other.range.lowerBound
      && range.upperBound >= other.range.upperBound
  }
}
