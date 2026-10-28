struct SourceLayoutContent {
  struct Change {
    enum Value {
      case text(String)
      case layout(SourceLayoutPrepared)
    }

    let range: Range<Int>
    let value: Value
  }

  let source: SourceSlice
  let originalIndentation: String
  let baseline: String
  let changes: [Change]

  func document(indentation: String) throws -> SourceLayoutDocument {
    let projected = try SourceLayoutText(
      source.text, originalIndentation: originalIndentation,
      indentation: indentation
    )
    let bytes = Array(projected.text.utf8)
    var events: [SourceLayoutDocument.Event] = []
    var cursor = 0
    for change in changes {
      let lower = try projected.offset(change.range.lowerBound - source.range
        .lowerBound)
      let upper = try projected.offset(change.range.upperBound - source.range
        .lowerBound)
      events.append(.text(String(
        decoding: bytes[cursor..<lower],
        as: UTF8.self
      )))
      switch change.value {
      case let .text(text):
        events.append(.text(try SourceLayoutText(
          text, originalIndentation: originalIndentation,
          indentation: indentation
        ).text))
      case let .layout(layout):
        events.append(.layout(
          layout,
          originalText: String(decoding: bytes[lower..<upper], as: UTF8.self)
        ))
      }
      cursor = upper
    }
    events.append(.text(String(decoding: bytes[cursor...], as: UTF8.self)))
    return SourceLayoutDocument(events: events)
  }

  func measuredText(indentation: String) throws -> String {
    try SourceLayoutText(
      baseline, originalIndentation: originalIndentation,
      indentation: indentation
    ).text
  }
}
