package enum SourceLayoutRenderer {
  package struct Placement {
    package let column: Int
    package let indentation: String
    package let lineIndentation: String
    package var originalText: String?
    package var trailingText: String = ""
  }

  package enum Separator: Sendable {
    case space
    case newline
  }

  package struct Context: Sendable {
    package var initialColumn: Int
    package var initialIndentation: String
    package var baseIndentation: String
    package var indentationUnit: String
    package var lineEnding: String
    package var defaultSeparator: Separator
    package var defaultWidth: Int
    package var tabWidth: Int
    package var leadingWhitespace: String
    package var trailingWhitespace: String
    package var hasSourceBefore: Bool
    package var hasSourceAfter: Bool
    package var closingIndentation: String?

    package init(
      initialColumn: Int = 0,
      initialIndentation: String = "",
      baseIndentation: String = "",
      indentationUnit: String = "  ",
      lineEnding: String = "\n",
      defaultSeparator: Separator = .space,
      defaultWidth: Int = 100,
      tabWidth: Int = 8,
      leadingWhitespace: String = "",
      trailingWhitespace: String = "",
      hasSourceBefore: Bool = false,
      hasSourceAfter: Bool = false,
      closingIndentation: String? = nil
    ) {
      self.initialColumn = initialColumn
      self.initialIndentation = initialIndentation
      self.baseIndentation = baseIndentation
      self.indentationUnit = indentationUnit
      self.lineEnding = lineEnding
      self.defaultSeparator = defaultSeparator
      self.defaultWidth = defaultWidth
      self.tabWidth = max(tabWidth, 1)
      self.leadingWhitespace = leadingWhitespace
      self.trailingWhitespace = trailingWhitespace
      self.hasSourceBefore = hasSourceBefore
      self.hasSourceAfter = hasSourceAfter
      self.closingIndentation = closingIndentation
    }
  }

  package static func render(
    _ layout: SourceLayout,
    context: Context,
    resolve: @escaping (any SourceProviding, Placement) throws -> String,
    resolveEdit: @escaping (SourceFix.Edit, Placement) throws
      -> String = { edit, _ in edit.replacement }
  ) throws -> String {
    guard context.defaultWidth > 0
    else { throw SourceLayoutError.widthMustBePositive }
    let events = try events(
      for: layout.node,
      separator: context.defaultSeparator,
      resolve: resolve,
      resolveEdit: resolveEdit
    )
    guard !layout.sources.isEmpty else { return "" }
    var writer = Writer(context: context)
    return try writer.render(events)
  }

  private enum Boundary: Int, Comparable {
    case soft
    case newline
    case blankLine

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  private enum Event {
    case deferred((Placement) throws -> String)
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
      case .deferred, .line: true
      default: false
      }
    }
  }

  private static func events(
    for node: SourceLayout.Node,
    separator: Separator,
    resolve: @escaping (any SourceProviding, Placement) throws -> String,
    resolveEdit: @escaping (SourceFix.Edit, Placement) throws -> String
  ) throws -> [Event] {
    switch node {
    case let .source(source):
      return [.deferred { try resolve(source, $0) }]
    case let .edit(edit):
      return [.deferred { try resolveEdit(edit, $0) }]
    case let .sequence(children):
      var result: [Event] = []
      for child in children {
        let content = try events(
          for: child, separator: separator, resolve: resolve,
          resolveEdit: resolveEdit
        )
        guard !content.isEmpty else { continue }
        if !result.isEmpty {
          result.append(.boundary(separator == .space ? .soft : .newline))
        }
        result += content
      }
      return result
    case let .line(child):
      let content = try events(
        for: child, separator: .space, resolve: resolve,
        resolveEdit: resolveEdit
      )
      guard content.contains(where: \.hasText) else { return [] }
      return [.line(content)]
    case .blankLine:
      return [.boundary(.blankLine)]
    case .newline:
      return [.lineBoundary]
    case .softBreak:
      return [.boundary(.soft)]
    case let .indent(child), let .align(child):
      let content = try events(
        for: child, separator: separator, resolve: resolve,
        resolveEdit: resolveEdit
      )
      guard content.contains(where: \.hasText) else { return content }
      let start: Event = if case .indent = node { .indent } else { .align }
      return [start] + content + [.endIndentation]
    case let .wrap(width, child):
      if let width, width <= 0 { throw SourceLayoutError.widthMustBePositive }
      let content = try events(
        for: child, separator: .space, resolve: resolve,
        resolveEdit: resolveEdit
      )
      guard content.contains(where: \.hasText) else { return content }
      return [.wrap(width)] + content + [.endWrap]
    }
  }

  private struct Writer {
    let context: Context
    var text = ""
    var column: Int
    var lineIndentation: String
    var pending: Boundary?
    var indentations: [String]
    var widths: [Int] = []
    var hasContent = false
    var startsWithLine = false
    var endsWithLine = false

    init(context: Context) {
      self.context = context
      column = context.initialColumn
      lineIndentation = context.initialIndentation
      indentations = [context.baseIndentation]
    }

    mutating func render(_ events: [Event]) throws -> String {
      for event in events {
        switch event {
        case let .deferred(make):
          _ = try appendDeferred(make)
        case let .line(events):
          try appendLine(events)
        case let .boundary(boundary):
          pending = max(pending ?? boundary, boundary)
        case .lineBoundary:
          requestLine()
        case .indent:
          indentations.append(indentation + context.indentationUnit)
        case .align:
          let start = columnAfterPendingBoundary
          let padding = max(
            0,
            start - endColumn(of: context.baseIndentation, startingAt: 0)
          )
          indentations.append(
            context.baseIndentation
              + String(
                repeating: " ",
                count: padding
              )
          )
        case .endIndentation:
          indentations.removeLast()
        case let .wrap(width):
          widths.append(width ?? context.defaultWidth)
        case .endWrap:
          widths.removeLast()
        }
      }
      guard hasContent else { return emptyReplacement }
      if endsWithLine, context.hasSourceAfter {
        text += context
          .lineEnding + (context.closingIndentation ?? context.baseIndentation)
      } else {
        text += context.trailingWhitespace
      }
      return text
    }

    private var emptyReplacement: String {
      let closingIndentation = context.closingIndentation ?? context
        .baseIndentation
      if startsWithLine && context.hasSourceBefore || endsWithLine && context
        .hasSourceAfter
      {
        return context
          .lineEnding + (context.hasSourceAfter ? closingIndentation : "")
      }
      guard context.hasSourceBefore, context.hasSourceAfter else { return "" }
      let lineCount = max(
        context.leadingWhitespace.filter(\.isSourceLayoutNewline).count,
        context.trailingWhitespace.filter(\.isSourceLayoutNewline).count
      )
      if lineCount > 0 {
        return String(repeating: context.lineEnding, count: lineCount) +
          closingIndentation
      }
      return context.leadingWhitespace.isEmpty && context.trailingWhitespace
        .isEmpty ? "" : " "
    }

    private var indentation: String {
      indentations.last ?? context.baseIndentation
    }

    private var placement: Placement {
      let startsLine = pending != nil && (
        hasContent ? pending != .soft : startsWithLine && context
          .hasSourceBefore
      )
      return Placement(
        column: columnAfterPendingBoundary, indentation: indentation,
        lineIndentation: startsLine ? indentation : lineIndentation
      )
    }

    private mutating func appendDeferred(
      _ make: (Placement) throws -> String
    ) throws -> Bool {
      let predicted = placement
      let preview = try make(predicted)
      guard !preview.isEmpty else { return false }
      let boundary = resolvedBoundary(before: preview)
      let actual = if hasContent, let boundary, boundary != .soft {
        Placement(
          column: endColumn(of: indentation, startingAt: 0),
          indentation: indentation, lineIndentation: indentation
        )
      } else { predicted }
      let value = if actual.column == predicted.column,
                     actual.lineIndentation == predicted.lineIndentation
      {
        preview
      } else { try make(actual) }
      guard !value.isEmpty else { return false }
      flushBoundary(boundary)
      append(value)
      hasContent = true
      endsWithLine = false
      return true
    }

    private mutating func requestLine() {
      pending = max(pending ?? .newline, .newline)
      if !hasContent { startsWithLine = true }
      endsWithLine = true
    }

    private mutating func appendLine(_ events: [Event]) throws {
      let previousPending = pending
      let previousStart = startsWithLine
      let previousEnd = endsWithLine
      let tabWidth = context.tabWidth
      requestLine()
      if try appendDeferred({ try Self.line(events, at: $0, tabWidth: tabWidth)
      }) {
        requestLine()
      } else {
        pending = previousPending
        startsWithLine = previousStart
        endsWithLine = previousEnd
      }
    }

    private static func line(
      _ events: [Event],
      at placement: Placement,
      tabWidth: Int
    ) throws -> String {
      var result = ""
      var pending: Boundary?
      var column = placement.column
      func append(_ value: String) throws {
        guard !value.isEmpty else { return }
        guard !value.contains(where: \.isSourceLayoutNewline) else {
          throw SourceLayoutError.lineContainsNewline
        }
        if !result.isEmpty, let pending {
          guard pending == .soft
          else { throw SourceLayoutError.lineContainsNewline }
          result += " "
          column += 1
        }
        result += value
        column = SourceTextWidth.column(
          after: value, startingAt: column, tabWidth: tabWidth
        )
        pending = nil
      }
      for event in events {
        let start = column + (!result.isEmpty && pending != nil ? 1 : 0)
        let current = Placement(
          column: start, indentation: placement.indentation,
          lineIndentation: placement.lineIndentation
        )
        switch event {
        case let .deferred(make): try append(make(current))
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

    private var columnAfterPendingBoundary: Int {
      guard let pending else { return column }
      if !hasContent {
        return startsWithLine && context.hasSourceBefore
          ? endColumn(of: indentation, startingAt: 0) : column
      }
      switch pending {
      case .soft: return column + 1
      case .newline, .blankLine:
        return endColumn(
          of: indentation,
          startingAt: 0
        )
      }
    }

    private func resolvedBoundary(before value: String) -> Boundary? {
      guard let pending else { return nil }
      return if pending == .soft, let width = widths.last,
                endColumn(
                  of:
                  value
                    .prefix { !$0.isSourceLayoutNewline },
                  startingAt: column + 1
                ) > width
      {
        .newline
      } else {
        pending
      }
    }

    private mutating func flushBoundary(_ boundary: Boundary?) {
      defer { pending = nil }
      if !hasContent {
        if startsWithLine, context.hasSourceBefore {
          text += context.lineEnding + indentation
          column = endColumn(of: indentation, startingAt: 0)
          lineIndentation = indentation
        } else {
          text += context.leadingWhitespace
        }
        return
      }
      guard let boundary else { return }
      switch boundary {
      case .soft:
        text += " "
        column += 1
      case .newline, .blankLine:
        text += context.lineEnding
        if boundary == .blankLine { text += context.lineEnding }
        text += indentation
        column = endColumn(of: indentation, startingAt: 0)
        lineIndentation = indentation
      }
    }

    private mutating func append(_ value: String) {
      text += value
      column = endColumn(of: value, startingAt: column)
      if value.contains(where: \.isSourceLayoutNewline) {
        lineIndentation = SourceLayoutText
          .indentation(in: SourceLayoutText.lastLine(in: value))
      }
    }

    private func endColumn(
      of text: some StringProtocol,
      startingAt start: Int
    ) -> Int {
      SourceTextWidth.column(
        after: text,
        startingAt: start,
        tabWidth: context.tabWidth
      )
    }
  }
}

extension Character {
  fileprivate var isSourceLayoutNewline: Bool {
    self == "\n" || self == "\r" || self == "\r\n"
  }
}
