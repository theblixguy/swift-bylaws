struct SourceLayoutDocument {
  enum Boundary: Int, Comparable {
    case soft
    case newline
    case blankLine

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  enum Event {
    case text(String)
    // Indirection keeps text and boundary events small.
    indirect case content(SourceLayoutContent)
    indirect case element(SourceLayoutContent, separator: String)
    indirect case layout(SourceLayoutPrepared, originalText: String?)
    case line([Event])
    case boundary(Boundary)
    case lineBoundary
    case indent
    case align
    case endIndentation
    case wrap(Int?)
    case endWrap

    var hasText: Bool {
      switch self {
      case let .text(text): !text.isEmpty
      case let .content(content): !content.baseline.isEmpty
      case let .element(content, separator): !content.baseline
        .isEmpty || !separator.isEmpty
      case let .layout(layout, _): !layout.baseline.isEmpty
      case let .line(events): events.contains(where: \.hasText)
      case .boundary, .lineBoundary, .indent, .align, .endIndentation,
           .wrap, .endWrap: false
      }
    }
  }

  let events: [Event]

  init(events: [Event]) { self.events = events }

  init(
    _ node: SourceLayout.Node,
    separator: SourceLayoutRenderer.Separator,
    source: (any SourceProviding) throws -> Event,
    edit: (SourceFix.Edit) throws -> Event
  ) throws {
    func lower(
      _ node: SourceLayout.Node,
      separator: SourceLayoutRenderer.Separator,
      into events: inout [Event]
    ) throws -> Bool {
      switch node {
      case let .source(provider):
        let event = try source(provider)
        events.append(event)
        return event.hasText
      case let .edit(value):
        let event = try edit(value)
        events.append(event)
        return event.hasText
      case let .sequence(children):
        let start = events.count
        var hasText = false
        for child in children {
          let previousEnd = events.count
          if previousEnd > start {
            events.append(.boundary(separator == .space ? .soft : .newline))
          }
          let childStart = events.count
          let childHasText = try lower(
            child, separator: separator, into: &events
          )
          hasText = hasText || childHasText
          if events.count == childStart, childStart > previousEnd {
            events.removeLast()
          }
        }
        return hasText
      case let .line(child):
        var contents: [Event] = []
        guard try lower(child, separator: .space, into: &contents) else {
          return false
        }
        events.append(.line(contents))
        return true
      case .blankLine:
        events.append(.boundary(.blankLine))
        return false
      case .newline:
        events.append(.lineBoundary)
        return false
      case .softBreak:
        events.append(.boundary(.soft))
        return false
      case let .indent(child), let .align(child):
        let start = events.count
        let opening: Event = if case .indent = node { .indent } else { .align }
        events.append(opening)
        let hasText = try lower(child, separator: separator, into: &events)
        if hasText {
          events.append(.endIndentation)
        } else if events.count == start + 1 {
          events.removeLast()
        } else {
          events.remove(at: start)
        }
        return hasText
      case let .wrap(width, child):
        if let width, width <= 0 { throw SourceLayoutError.widthMustBePositive }
        let start = events.count
        events.append(.wrap(width))
        let hasText = try lower(child, separator: .space, into: &events)
        if hasText {
          events.append(.endWrap)
        } else if events.count == start + 1 {
          events.removeLast()
        } else {
          events.remove(at: start)
        }
        return hasText
      }
    }
    var events: [Event] = []
    _ = try lower(node, separator: separator, into: &events)
    self.events = events
  }
}
