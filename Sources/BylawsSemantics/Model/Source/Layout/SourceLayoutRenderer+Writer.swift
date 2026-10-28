extension SourceLayoutRenderer {
  struct Writer {
    let context: Context
    var text = ""
    var cursor: SourceLayoutCursor
    var column: Int {
      get { cursor.column }
      set { cursor.column = newValue }
    }

    var lineIndentation: String {
      get { cursor.indentation }
      set { cursor.indentation = newValue }
    }

    var pending: Boundary?
    var indentations: [String]
    var widths: [Int] = []
    var hasContent = false
    var startsWithLine = false
    var endsWithLine = false

    init(context: Context) {
      self.context = context
      cursor = SourceLayoutCursor(
        column: context.initialColumn, indentation: context.initialIndentation,
        tabWidth: context.tabWidth
      )
      indentations = [context.baseIndentation]
    }

    mutating func render(
      _ events: [Event], followedBy following: SourceLayoutContinuation
    ) throws -> String {
      let lastContent = events.last {
        switch $0 {
        case .lineBoundary: true
        default: $0.hasText
        }
      }
      let endsOnLine = if case .line = lastContent { true }
      else if case .lineBoundary = lastContent { true } else { false }
      let trailing = endsOnLine && context.hasSourceAfter
        ? context
        .lineEnding + (context.closingIndentation ?? context.baseIndentation)
        : context.trailingWhitespace
      let terminal = SourceLayoutContinuation.events(
        [.text(trailing)][...],
        following
      )
      for (index, event) in events.enumerated() {
        let remaining = SourceLayoutContinuation.scope(
          events[(index + 1)...],
          terminal
        )
        switch event {
        case .text, .content, .element, .layout:
          _ = try appendContent(event, followedBy: remaining)
        case let .line(children):
          try appendLine(children)
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
        context.leadingWhitespace.filter(SourceLayoutText.isNewline).count,
        context.trailingWhitespace.filter(SourceLayoutText.isNewline).count
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

    private mutating func appendContent(
      _ event: Event, followedBy following: SourceLayoutContinuation
    ) throws -> Bool {
      let predicted = placement
      let preview = try SourceLayoutRenderer.resolve(
        event, at: predicted, followedBy: following, tabWidth: context.tabWidth
      )
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
      } else {
        try SourceLayoutRenderer.resolve(
          event,
          at: actual,
          followedBy: following,
          tabWidth: context.tabWidth
        )
      }
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
      requestLine()
      let predicted = placement
      let value = try SourceLayoutRenderer.line(
        events,
        at: predicted,
        tabWidth: context.tabWidth
      )
      if value.isEmpty {
        pending = previousPending
        startsWithLine = previousStart
        endsWithLine = previousEnd
      } else {
        let boundary = resolvedBoundary(before: value)
        flushBoundary(boundary)
        append(value)
        hasContent = true
        requestLine()
      }
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
                    .prefix { !SourceLayoutText.isNewline($0) },
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
      cursor.advance(value)
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
