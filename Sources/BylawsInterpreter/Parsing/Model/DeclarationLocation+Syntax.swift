import BylawsSemantics
import BylawsSyntax

extension DeclarationLocation {
  init(
    of node: some SyntaxProtocol,
    converter: SourceLocationConverter,
    filePath: String
  ) {
    let start = node.positionAfterSkippingLeadingTrivia
    let position = converter.location(for: start)
    self.init(
      filePath: filePath,
      line: position.line,
      column: position.column,
      utf8Offset: start.utf8Offset
    )
  }
}
