public import BylawsSyntax

extension SourceSlice {
  /// Returns a replacement for the syntax node with this exact source range.
  ///
  /// The replacement preserves the original node's outer trivia. The closure
  /// receives a node from the complete original file.
  ///
  /// - Throws: ``SourceError/syntaxMismatch`` when the slice does not match
  ///   the requested type and range, or an error from the transform.
  public func replacing<S: SyntaxProtocol>(
    as syntaxType: S.Type,
    _ transform: (S) throws -> S
  ) throws -> SourceFix.Edit {
    var candidate = snapshot.token(at: range.lowerBound)
      .map(Syntax.init)
    while let node = candidate {
      if node.positionAfterSkippingLeadingTrivia.utf8Offset == range.lowerBound,
         node.endPositionBeforeTrailingTrivia.utf8Offset == range.upperBound,
         let original = node.as(syntaxType)
      {
        return try replacement(with: transform(original).trimmedDescription)
      }
      candidate = node.parent
    }
    throw SourceError.syntaxMismatch
  }
}
