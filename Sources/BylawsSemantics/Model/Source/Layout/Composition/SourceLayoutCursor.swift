struct SourceLayoutCursor {
  var column: Int
  var indentation: String
  let tabWidth: Int

  mutating func advance(_ text: String) {
    let wasIndentation = column == SourceTextWidth.column(
      after: indentation, tabWidth: tabWidth
    )
    column = SourceTextWidth.column(
      after: text, startingAt: column, tabWidth: tabWidth
    )
    if text.contains(where: SourceLayoutText.isNewline) {
      indentation = SourceLayoutText.indentation(
        in: SourceLayoutText.lastLine(in: text)
      )
    } else if wasIndentation {
      indentation += SourceLayoutText.indentation(in: text)
    }
  }
}
