import BylawsSyntax

struct SourceText: Sendable {
  let buffer: SourceBuffer
  let swiftLanguageMode: SwiftLanguageMode
  private let lines: SourceLineTable

  init(
    source: String, swiftLanguageMode: SwiftLanguageMode = .v6,
    filePath: String? = nil
  ) {
    self.swiftLanguageMode = swiftLanguageMode
    lines = SourceLineTable(source.utf8)
    buffer = SourceBuffer(
      source,
      lineCount: source.isEmpty ? 0 : lines.count,
      snapshot: filePath.map {
        SourceSnapshot(
          filePath: $0,
          text: source,
          swiftLanguageMode: swiftLanguageMode
        )
      }
    )
  }

  init(
    buffer: SourceBuffer, swiftLanguageMode: SwiftLanguageMode,
    parsedTree: SourceFileSyntax? = nil
  ) {
    self.swiftLanguageMode = swiftLanguageMode
    self.buffer = if let parsedTree, let snapshot = buffer.snapshot {
      SourceBuffer(
        buffer.text, lineCount: buffer.lineCount,
        snapshot: snapshot.withSyntaxTree(parsedTree)
      )
    } else {
      buffer
    }
    lines = SourceLineTable(buffer.text.utf8)
  }

  init(
    source: String, swiftLanguageMode: SwiftLanguageMode,
    originalSource: SourceSlice?
  ) {
    self.swiftLanguageMode = swiftLanguageMode
    lines = SourceLineTable(source.utf8)
    buffer = SourceBuffer(
      source, lineCount: source.isEmpty ? 0 : lines.count,
      snapshot: originalSource.flatMap {
        $0.text.utf8.elementsEqual(source.utf8) ? $0.snapshot : nil
      }
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
