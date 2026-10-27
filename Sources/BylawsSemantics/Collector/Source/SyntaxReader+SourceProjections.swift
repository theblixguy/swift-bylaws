import BylawsSyntax

extension SyntaxReader {
  func parsedSource(
    of node: some SyntaxProtocol, nameRange: Range<Int>? = nil
  ) -> ParsedSource? {
    guard text.buffer.sourcePath != nil else { return nil }
    return ParsedSource(
      buffer: text.buffer, range: text.trimmedRange(of: node),
      nameRange: nameRange
    )
  }

  func parsedSource(
    of node: some SyntaxProtocol, name: some SyntaxProtocol
  ) -> ParsedSource? {
    parsedSource(of: node, nameRange: text.trimmedRange(of: name))
  }
}
