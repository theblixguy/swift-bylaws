indirect enum SourceLayoutContinuation {
  case end
  case events(ArraySlice<SourceLayoutDocument.Event>, SourceLayoutContinuation)
  case scope(ArraySlice<SourceLayoutDocument.Event>, SourceLayoutContinuation)

  init(text: String) {
    self = .events([.text(text)][...], .end)
  }

  func firstLine() -> String {
    var result = ""
    var continuation = self
    var pending: SourceLayoutDocument.Boundary?
    func append(_ text: String) -> Bool {
      let line = text.prefix { !SourceLayoutText.isNewline($0) }
      result += line
      return line.count == text.count
    }
    while true {
      let events: ArraySlice<SourceLayoutDocument.Event>
      let next: SourceLayoutContinuation
      let endsScope: Bool
      switch continuation {
      case .end: return result
      case let .events(values, following):
        (events, next, endsScope) = (values, following, false)
      case let .scope(values, following):
        (events, next, endsScope) = (values, following, true)
      }
      let inheritedBoundary = pending
      var emittedText = false
      for event in events {
        let text: String
        switch event {
        case let .text(value): text = value
        case let .content(content): text = content.baseline
        case let .element(content, separator): text = content
          .baseline + separator
        case let .layout(layout, _): text = layout.baseline
        case let .line(children):
          if children.contains(where: \.hasText) { return result }
          continue
        case let .boundary(boundary):
          pending = max(pending ?? boundary, boundary)
          continue
        case .lineBoundary:
          pending = .newline
          continue
        case .indent, .align, .endIndentation, .wrap, .endWrap: continue
        }
        guard !text.isEmpty else { continue }
        if let pending {
          guard pending == .soft else { return result }
          result += " "
        }
        pending = nil
        emittedText = true
        guard append(text) else { return result }
      }
      if endsScope { pending = emittedText ? nil : inheritedBoundary }
      continuation = next
    }
  }
}
