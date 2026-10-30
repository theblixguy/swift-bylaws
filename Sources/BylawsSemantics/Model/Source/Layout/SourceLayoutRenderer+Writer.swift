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

    private enum Resume {
      case preview(Event, Placement, SourceLayoutContinuation)
      case placed(Boundary?)
      case line(Boundary?, startsWithLine: Bool, endsWithLine: Bool)
    }

    private let events: [Event]
    private let terminal: SourceLayoutContinuation
    private var index = 0
    private var resume: Resume?

    init(
      document: SourceLayoutDocument, context: Context,
      followedBy following: SourceLayoutContinuation
    ) {
      self.context = context
      events = document.events
      cursor = SourceLayoutCursor(
        column: context.initialColumn, indentation: context.initialIndentation,
        tabWidth: context.tabWidth
      )
      indentations = [context.baseIndentation]
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
      terminal = .events([.text(trailing)][...], following)
    }

    mutating func advance(after value: String?) throws -> Step {
      if let value, let resume {
        self.resume = nil
        if let request = try accept(value, after: resume) {
          return .render(request)
        }
      }
      while index < events.count {
        let event = events[index]
        index += 1
        switch event {
        case .text, .content, .element, .layout:
          let predicted = placement
          if let value = try SourceLayoutRenderer.literal(
            event,
            indentation: predicted.indentation
          ) {
            if !value.isEmpty {
              appendContent(value, boundary: resolvedBoundary(before: value))
            }
            continue
          }
          let remaining = SourceLayoutContinuation.scope(
            events[index...],
            terminal
          )
          let request = try SourceLayoutRenderer.request(
            event, at: predicted, followedBy: remaining,
            tabWidth: context.tabWidth
          )
          let state = Resume.preview(event, predicted, remaining)
          if case let .text(value) = request {
            if let request = try accept(value, after: state) {
              return .render(request)
            }
          } else {
            resume = state
            return .render(request)
          }
        case let .line(children):
          resume = .line(
            pending,
            startsWithLine: startsWithLine,
            endsWithLine: endsWithLine
          )
          requestLine()
          return .render(.line(
            children,
            at: placement,
            tabWidth: context.tabWidth
          ))
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
      guard hasContent else { return .complete(emptyReplacement) }
      if endsWithLine, context.hasSourceAfter {
        text += context
          .lineEnding + (context.closingIndentation ?? context.baseIndentation)
      } else {
        text += context.trailingWhitespace
      }
      return .complete(text)
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

    private mutating func accept(
      _ value: String,
      after state: Resume
    ) throws -> Request? {
      switch state {
      case let .preview(event, predicted, following):
        guard !value.isEmpty else { return nil }
        let boundary = resolvedBoundary(before: value)
        let actual = if hasContent, let boundary, boundary != .soft {
          Placement(
            column: endColumn(of: indentation, startingAt: 0),
            indentation: indentation, lineIndentation: indentation
          )
        } else { predicted }
        if actual.column != predicted.column || actual
          .lineIndentation != predicted.lineIndentation
        {
          let request = try SourceLayoutRenderer.request(
            event, at: actual, followedBy: following, tabWidth: context.tabWidth
          )
          if case let .text(value) = request {
            appendContent(value, boundary: boundary)
          } else {
            resume = .placed(boundary)
            return request
          }
        } else { appendContent(value, boundary: boundary) }
      case let .placed(boundary):
        appendContent(value, boundary: boundary)
      case let .line(previousPending, previousStart, previousEnd):
        if value.isEmpty {
          pending = previousPending
          startsWithLine = previousStart
          endsWithLine = previousEnd
        } else {
          flushBoundary(resolvedBoundary(before: value))
          append(value)
          hasContent = true
          requestLine()
        }
      }
      return nil
    }

    private mutating func appendContent(_ value: String, boundary: Boundary?) {
      guard !value.isEmpty else { return }
      flushBoundary(boundary)
      append(value)
      hasContent = true
      endsWithLine = false
    }

    private mutating func requestLine() {
      pending = max(pending ?? .newline, .newline)
      if !hasContent { startsWithLine = true }
      endsWithLine = true
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
