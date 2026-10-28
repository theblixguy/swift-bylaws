import BylawsSyntax

struct SourceText: Sendable {
  let buffer: SourceBuffer
  let capturedBuffer: SourceBuffer
  let swiftLanguageMode: SwiftLanguageMode
  private let lines: SourceLineTable

  init(
    source: String, swiftLanguageMode: SwiftLanguageMode = .v6,
    filePath: String? = nil
  ) {
    self.swiftLanguageMode = swiftLanguageMode
    lines = SourceLineTable(source.utf8)
    let buffer = SourceBuffer(
      source,
      lineCount: source.isEmpty ? 0 : lines.count,
      filePath: filePath,
      swiftLanguageMode: swiftLanguageMode
    )
    self.buffer = buffer
    capturedBuffer = buffer
  }

  init(
    buffer: SourceBuffer, swiftLanguageMode: SwiftLanguageMode,
    parsedTree: SourceFileSyntax? = nil
  ) {
    self.swiftLanguageMode = swiftLanguageMode
    let capturedBuffer =
      if let parsedTree, let snapshot = buffer.snapshot,
      snapshot.parsedTree?.id != parsedTree.id {
        SourceBuffer(
          buffer.text, lineCount: buffer.lineCount,
          snapshot: snapshot.withSyntaxTree(parsedTree)
        )
      } else {
        buffer
      }
    self.buffer = capturedBuffer
    self.capturedBuffer = capturedBuffer
    lines = SourceLineTable(buffer.text.utf8)
  }

  init(
    source: String, swiftLanguageMode: SwiftLanguageMode,
    capturedBuffer: SourceBuffer
  ) {
    self.swiftLanguageMode = swiftLanguageMode
    lines = SourceLineTable(source.utf8)
    buffer = SourceBuffer(
      source, lineCount: source.isEmpty ? 0 : lines.count
    )
    self.capturedBuffer = capturedBuffer
  }

  func trimmedRange(of node: some SyntaxProtocol) -> Range<Int> {
    node.positionAfterSkippingLeadingTrivia
      .utf8Offset..<node.endPositionBeforeTrailingTrivia.utf8Offset
  }

  func trimmedText(of node: some SyntaxProtocol) -> String {
    buffer.text(inUTF8Range: trimmedRange(of: node))
  }

  func location(of position: AbsolutePosition) -> (line: Int, column: Int) {
    lines.location(at: position.utf8Offset)
  }
}
