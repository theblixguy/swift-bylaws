import BylawsSyntax

extension SyntaxReader {
  func parsedSource(of node: some SyntaxProtocol) -> ParsedSource? {
    guard text.buffer.sourcePath != nil else { return nil }
    return ParsedSource(buffer: text.buffer, range: text.trimmedRange(of: node))
  }
}
