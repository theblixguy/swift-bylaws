struct SourceLayoutDocument {
  enum Boundary: Int, Comparable {
    case soft
    case newline
    case blankLine

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  indirect enum Event {
    case text(String)
    case content(SourceLayoutContent)
    case element(SourceLayoutContent, separator: String)
    case layout(SourceLayoutPrepared, originalText: String?)
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
    source: (any SourceProviding) throws -> Self,
    edit: (SourceFix.Edit) throws -> Self
  ) throws {
    func lower(
      _ node: SourceLayout.Node,
      separator: SourceLayoutRenderer
        .Separator
    ) throws -> [Event] {
      switch node {
      case let .source(provider): return try source(provider).events
      case let .edit(value): return try edit(value).events
      case let .sequence(children):
        var result: [Event] = []
        for child in children {
          let events = try lower(child, separator: separator)
          guard !events.isEmpty else { continue }
          if !result.isEmpty {
            result.append(.boundary(separator == .space ? .soft : .newline))
          }
          result += events
        }
        return result
      case let .line(child):
        let events = try lower(child, separator: .space)
        return events.contains(where: \.hasText) ? [.line(events)] : []
      case .blankLine: return [.boundary(.blankLine)]
      case .newline: return [.lineBoundary]
      case .softBreak: return [.boundary(.soft)]
      case let .indent(child), let .align(child):
        let events = try lower(child, separator: separator)
        guard events.contains(where: \.hasText) else { return events }
        let start: Event = if case .indent = node { .indent } else { .align }
        return [start] + events + [.endIndentation]
      case let .wrap(width, child):
        if let width, width <= 0 { throw SourceLayoutError.widthMustBePositive }
        let events = try lower(child, separator: .space)
        guard events.contains(where: \.hasText) else { return events }
        return [.wrap(width)] + events + [.endWrap]
      }
    }
    events = try lower(node, separator: separator)
  }
}
