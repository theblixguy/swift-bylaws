struct SourceLayoutPrepared {
  let source: SourceSlice
  let capture: SourceLayoutPlan
  let content: SourceLayoutContent
  let lookaheadText: String
  let document: SourceLayoutDocument
  let context: SourceLayoutRenderer.Context
  let originalPlacement: SourceLayoutRenderer.Placement
  let indentsContents: Bool
  let closesOwner: Bool
  let hasBaseIndentation: Bool
  var trimmed = false

  var maximumWidth: Int? { capture.lineWidthLimit }

  var baseline: String {
    trimmed ? Self.trim(lookaheadText) : lookaheadText
  }

  func projectedContext(
    at placement: SourceLayoutRenderer.Placement,
    tabWidth: Int
  )
    -> SourceLayoutRenderer.Context
  {
    var result = context
    let original = placement.originalText ?? source.text
    let leading = String(original.prefix(while: Self.isWhitespace))
    result.initialColumn = SourceTextWidth.column(
      after: leading, startingAt: placement.column, tabWidth: tabWidth
    )
    result.initialIndentation = leading
      .contains(where: SourceLayoutText.isNewline)
      ? SourceLayoutText.indentation(in: SourceLayoutText.lastLine(in: leading))
      : placement.lineIndentation
    result.baseIndentation = if hasBaseIndentation {
      placement.lineIndentation
    } else if indentsContents {
      placement.lineIndentation + context.indentationUnit
    } else { placement.lineIndentation }
    result.closingIndentation = closesOwner
      ? placement.lineIndentation : result.baseIndentation
    result.leadingWhitespace = leading
    result.trailingWhitespace = String(original.reversed()
      .prefix(while: Self.isWhitespace).reversed())
    return result
  }

  static func trim(_ text: String) -> String {
    String(text.drop(while: isWhitespace).reversed()
      .drop(while: isWhitespace).reversed())
  }

  private static func isWhitespace(_ character: Character) -> Bool {
    character == " " || character == "\t" || SourceLayoutText
      .isNewline(character)
  }
}
