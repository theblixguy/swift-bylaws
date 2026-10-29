extension SourceLayoutRenderer {
  struct LineWriter {
    private let events: [Event]
    private let placement: Placement
    private let tabWidth: Int
    private var index = 0
    private var text = ""
    private var pending: Boundary?
    private var cursor: SourceLayoutCursor
    private var nestedLine = false

    init(events: [Event], at placement: Placement, tabWidth: Int) {
      self.events = events
      self.placement = placement
      self.tabWidth = tabWidth
      cursor = SourceLayoutCursor(
        column: placement.column, indentation: placement.lineIndentation,
        tabWidth: tabWidth
      )
    }

    mutating func advance(after value: String?) throws -> Step {
      if let value {
        if nestedLine {
          nestedLine = false
          if !value.isEmpty {
            guard text.isEmpty
            else { throw SourceLayoutError.lineContainsNewline }
            try append(value)
            pending = .newline
          }
        } else { try append(value) }
      }
      while index < events.count {
        let event = events[index]
        index += 1
        let start = cursor.column + (!text.isEmpty && pending != nil ? 1 : 0)
        let current = Placement(
          column: start, indentation: placement.indentation,
          lineIndentation: placement.lineIndentation
        )
        switch event {
        case .text, .content, .element, .layout:
          if let value = try SourceLayoutRenderer.literal(
            event,
            indentation: current.indentation
          ) {
            try append(value)
            continue
          }
          let following = SourceLayoutContinuation.scope(
            events[index...], .init(text: "\n")
          )
          let request = try SourceLayoutRenderer.request(
            event, at: current, followedBy: following, tabWidth: tabWidth
          )
          if case let .text(value) = request { try append(value) }
          else { return .render(request) }
        case let .line(children):
          nestedLine = true
          return .render(.line(children, at: current, tabWidth: tabWidth))
        case let .boundary(value): pending = max(pending ?? value, value)
        case .lineBoundary: pending = max(pending ?? .newline, .newline)
        case .indent, .align, .endIndentation, .wrap, .endWrap: break
        }
      }
      return .complete(text)
    }

    private mutating func append(_ value: String) throws {
      guard !value.isEmpty else { return }
      guard !value.contains(where: SourceLayoutText.isNewline) else {
        throw SourceLayoutError.lineContainsNewline
      }
      if !text.isEmpty, let pending {
        guard pending == .soft
        else { throw SourceLayoutError.lineContainsNewline }
        text += " "
        cursor.advance(" ")
      }
      text += value
      cursor.advance(value)
      pending = nil
    }
  }
}
