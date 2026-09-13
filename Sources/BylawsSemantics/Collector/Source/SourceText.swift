import SwiftSyntax

struct SourceText {
  let buffer: SourceBuffer
  private let lines: SourceLineTable

  init(source: String) {
    lines = SourceLineTable(source.utf8)
    buffer = SourceBuffer(
      source,
      lineCount: source.isEmpty ? 0 : lines.count
    )
  }

  func trimmedRange(of node: some SyntaxProtocol) -> Range<Int> {
    node.positionAfterSkippingLeadingTrivia.utf8Offset
      ..< node.endPositionBeforeTrailingTrivia.utf8Offset
  }

  func trimmedText(of node: some SyntaxProtocol) -> String {
    buffer.text(inUTF8Range: trimmedRange(of: node))
  }

  func location(of position: AbsolutePosition) -> (line: Int, column: Int) {
    lines.location(at: position.utf8Offset)
  }
}
