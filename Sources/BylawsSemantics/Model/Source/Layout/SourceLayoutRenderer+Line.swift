extension SourceLayoutRenderer {
  static func line(
    _ events: [Event],
    at placement: Placement,
    tabWidth: Int
  ) throws -> String {
    var result = ""
    var pending: Boundary?
    var cursor = SourceLayoutCursor(
      column: placement.column, indentation: placement.lineIndentation,
      tabWidth: tabWidth
    )
    func append(_ value: String) throws {
      guard !value.isEmpty else { return }
      guard !value.contains(where: SourceLayoutText.isNewline) else {
        throw SourceLayoutError.lineContainsNewline
      }
      if !result.isEmpty, let pending {
        guard pending == .soft
        else { throw SourceLayoutError.lineContainsNewline }
        result += " "
        cursor.advance(" ")
      }
      result += value
      cursor.advance(value)
      pending = nil
    }
    for (index, event) in events.enumerated() {
      let start = cursor.column + (!result.isEmpty && pending != nil ? 1 : 0)
      let current = Placement(
        column: start, indentation: placement.indentation,
        lineIndentation: placement.lineIndentation
      )
      switch event {
      case .text, .content, .element, .layout:
        let following = SourceLayoutContinuation.scope(
          events[(index + 1)...], .init(text: "\n")
        )
        try append(SourceLayoutRenderer.resolve(
          event,
          at: current,
          followedBy: following,
          tabWidth: tabWidth
        ))
      case let .line(children):
        let value = try line(children, at: current, tabWidth: tabWidth)
        if !value.isEmpty {
          guard result.isEmpty
          else { throw SourceLayoutError.lineContainsNewline }
          try append(value)
          pending = .newline
        }
      case let .boundary(value): pending = max(pending ?? value, value)
      case .lineBoundary: pending = max(pending ?? .newline, .newline)
      case .indent, .align, .endIndentation, .wrap, .endWrap: break
      }
    }
    return result
  }
}
