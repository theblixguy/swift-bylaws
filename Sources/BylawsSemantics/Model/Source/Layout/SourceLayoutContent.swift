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
    if changes.isEmpty || indentation == originalIndentation
      && changes.allSatisfy({
        if case .text = $0.value { true } else { false }
      })
    {
      return SourceLayoutDocument(events: [.text(try measuredText(
        indentation: indentation
      ))])
    }
    let projected: SourceLayoutText?
    let bytes: [UInt8]
    let range: Range<Int>
    if indentation == originalIndentation,
       let sourceBytes = source.snapshot.syntaxContext?.bytes
    {
      projected = nil
      bytes = sourceBytes
      range = source.range
    } else {
      let text = try SourceLayoutText(
        source.text, originalIndentation: originalIndentation,
        indentation: indentation
      )
      projected = text
      bytes = Array(text.text.utf8)
      range = 0..<bytes.count
    }
    var events: [SourceLayoutDocument.Event] = []
    var cursor = range.lowerBound
    for change in changes {
      let lower = try projected?.offset(change.range.lowerBound - source.range
        .lowerBound) ?? change.range.lowerBound
      let upper = try projected?.offset(change.range.upperBound - source.range
        .lowerBound) ?? change.range.upperBound
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
    events.append(.text(String(
      decoding: bytes[cursor..<range.upperBound],
      as: UTF8.self
    )))
    return SourceLayoutDocument(events: events)
  }

  func measuredText(indentation: String) throws -> String {
    if indentation == originalIndentation
      || !baseline.contains(where: SourceLayoutText.isNewline)
    {
      return baseline
    }
    return try SourceLayoutText(
      baseline, originalIndentation: originalIndentation,
      indentation: indentation
    ).text
  }
}
