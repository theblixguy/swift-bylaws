indirect enum SourceLayoutContinuation {
  case end
  case events(ArraySlice<SourceLayoutDocument.Event>, SourceLayoutContinuation)
  case scope(ArraySlice<SourceLayoutDocument.Event>, SourceLayoutContinuation)

  init(text: String) {
    self = .events([.text(text)][...], .end)
  }

  func firstLine() -> String {
    var result = ""
    readFirstLine { text in
      let line = text.prefix { !SourceLayoutText.isNewline($0) }
      result += line
      return line.count == text.count
    }
    return result
  }

  func exceeds(
    _ maximumWidth: Int, after text: String, startingAt column: Int,
    tabWidth: Int
  ) -> Bool {
    guard !text.isEmpty else { return false }
    guard column <= maximumWidth else { return true }
    var measurement = WidthMeasurement(
      maximumWidth: maximumWidth, startingAt: column, tabWidth: tabWidth
    )
    guard measurement.append(text, stoppingAtNewline: false)
    else { return true }
    if text.last.map(SourceLayoutText.isNewline) != true {
      readFirstLine { measurement.append($0, stoppingAtNewline: true) }
    }
    measurement.finish()
    return measurement.exceeded
  }

  private func readFirstLine(_ append: (String) -> Bool) {
    var continuation = self
    var pending: SourceLayoutDocument.Boundary?
    while true {
      let events: ArraySlice<SourceLayoutDocument.Event>
      let next: SourceLayoutContinuation
      let endsScope: Bool
      switch continuation {
      case .end: return
      case let .events(values, following):
        (events, next, endsScope) = (values, following, false)
      case let .scope(values, following):
        (events, next, endsScope) = (values, following, true)
      }
      let inheritedBoundary = pending
      var emittedText = false
      for event in events {
        let fragments: (text: String, separator: String)
        switch event {
        case let .text(value): fragments = (value, "")
        case let .content(content): fragments = (content.baseline, "")
        case let .element(content, separator): fragments = (
            content.baseline, separator
          )
        case let .layout(layout, _): fragments = (layout.baseline, "")
        case let .line(children):
          if children.contains(where: \.hasText) { return }
          continue
        case let .boundary(boundary):
          pending = max(pending ?? boundary, boundary)
          continue
        case .lineBoundary:
          pending = .newline
          continue
        case .indent, .align, .endIndentation, .wrap, .endWrap: continue
        }
        guard !fragments.text.isEmpty || !fragments.separator.isEmpty
        else { continue }
        if let pending {
          guard pending == .soft, append(" ") else { return }
        }
        pending = nil
        emittedText = true
        guard append(fragments.text), append(fragments.separator)
        else { return }
      }
      if endsScope { pending = emittedText ? nil : inheritedBoundary }
      continuation = next
    }
  }

  private struct WidthMeasurement {
    let maximumWidth: Int
    let tabWidth: Int
    var column: Int
    var pendingGrapheme: Character?
    var exceeded = false

    init(maximumWidth: Int, startingAt column: Int, tabWidth: Int) {
      self.maximumWidth = maximumWidth
      self.tabWidth = max(tabWidth, 1)
      self.column = column
    }

    mutating func append(_ text: String, stoppingAtNewline: Bool) -> Bool {
      var characters = text.makeIterator()
      guard let first = characters.next() else { return true }
      let hasKnownBoundaries = if let previous = pendingGrapheme {
        previous.asciiValue != nil && first.asciiValue != nil
          && !(previous == "\r" && first == "\n")
      } else { true }
      var character: Character? = first
      while let current = character {
        if stoppingAtNewline, SourceLayoutText.isNewline(current) {
          finish()
          return false
        }
        if hasKnownBoundaries {
          if let pendingGrapheme { advance(pendingGrapheme) }
          pendingGrapheme = current
        } else { append(current) }
        if exceeded { return false }
        character = characters.next()
      }
      return true
    }

    mutating func finish() {
      if let pendingGrapheme { advance(pendingGrapheme) }
      pendingGrapheme = nil
    }

    private mutating func append(_ character: Character) {
      guard let previous = pendingGrapheme else {
        pendingGrapheme = character
        return
      }
      if previous.asciiValue != nil, character.asciiValue != nil {
        if previous == "\r", character == "\n" {
          pendingGrapheme = "\r\n"
        } else {
          advance(previous)
          pendingGrapheme = character
        }
        return
      }
      // A following fragment can extend the last grapheme.
      var characters = (String(previous) + String(character)).makeIterator()
      var last = characters.next()
      while let next = characters.next() {
        if let last { advance(last) }
        guard !exceeded else { return }
        last = next
      }
      pendingGrapheme = last
    }

    private mutating func advance(_ character: Character) {
      if SourceLayoutText.isNewline(character) {
        column = 0
        return
      }
      let advance = character == "\t" ? tabWidth - column % tabWidth : 1
      if advance > maximumWidth - column {
        exceeded = true
      } else {
        column += advance
      }
    }
  }
}
