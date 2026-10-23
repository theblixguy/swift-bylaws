package enum SourceLayoutRenderer {
  package enum Separator: Sendable {
    case space
    case newline
  }

  package struct Context: Sendable {
    package var initialColumn: Int
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
    resolve: (any SourceProviding) throws -> String,
    resolveEdit: (SourceFix.Edit) throws -> String = { $0.replacement }
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
    var writer = Writer(
      context: context,
      startsWithLine: events.prefix(while: { !$0.hasText })
        .contains(where: \.isLineBoundary),
      endsWithLine: events.reversed().prefix(while: { !$0.hasText })
        .contains(where: \.isLineBoundary)
    )
    return try writer.render(events)
  }

  private enum Boundary: Int, Comparable {
    case soft
    case newline
    case blankLine

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  private enum Event {
    case text(String, indentation: String)
    case boundary(Boundary)
    case lineBoundary
    case indent
    case align
    case endIndentation
    case wrap(Int?)
    case endWrap

    var hasText: Bool {
      if case .text = self { true } else { false }
    }

    var isLineBoundary: Bool {
      if case .lineBoundary = self { true } else { false }
    }
  }

  private static func events(
    for node: SourceLayout.Node,
    separator: Separator,
    resolve: (any SourceProviding) throws -> String,
    resolveEdit: (SourceFix.Edit) throws -> String
  ) throws -> [Event] {
    switch node {
    case let .source(source):
      let text = try resolve(source)
      return text.isEmpty
        ? []
        : [
          .text(
            text,
            indentation: try originalIndentation(of: source)
          ),
        ]
    case let .edit(edit):
      let text = try resolveEdit(edit)
      return text.isEmpty
        ? []
        : [
          .text(
            text,
            indentation: originalIndentation(of: edit.source)
          ),
        ]
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
      var text = ""
      var pending: Boundary?
      for event in content {
        switch event {
        case let .text(value, _):
          guard !value.contains(where: \.isSourceLayoutNewline) else {
            throw SourceLayoutError.lineContainsNewline
          }
          if !text.isEmpty, let pending {
            guard pending == .soft
            else { throw SourceLayoutError.lineContainsNewline }
            text += " "
          }
          text += value
          pending = nil
        case let .boundary(boundary):
          pending = max(pending ?? boundary, boundary)
        case .lineBoundary:
          pending = max(pending ?? .newline, .newline)
        case .indent, .align, .endIndentation, .wrap, .endWrap: break
        }
      }
      return [
        .lineBoundary,
        .text(text, indentation: ""),
        .lineBoundary,
      ]
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

  private static func originalIndentation(
    of provider: any SourceProviding
  ) throws
    -> String
  {
    originalIndentation(of: try provider.source)
  }

  private static func originalIndentation(of source: SourceSlice) -> String {
    let bytes = source.snapshot.text.utf8
    let end = bytes.index(bytes.startIndex, offsetBy: source.range.lowerBound)
    let lineStart =
      bytes[..<end].lastIndex { $0 == 0x0A || $0 == 0x0D }
        .map { bytes.index(after: $0) } ?? bytes.startIndex
    let indentation = bytes[lineStart..<end].prefix { $0 == 0x20 || $0 == 0x09 }
    return String(decoding: indentation, as: UTF8.self)
  }

  private struct Writer {
    let context: Context
    var text = ""
    var column: Int
    var pending: Boundary?
    var indentations: [String]
    var widths: [Int] = []
    var hasContent = false
    let startsWithLine: Bool
    let endsWithLine: Bool

    init(context: Context, startsWithLine: Bool, endsWithLine: Bool) {
      self.context = context
      column = context.initialColumn
      indentations = [context.baseIndentation]
      self.startsWithLine = startsWithLine
      self.endsWithLine = endsWithLine
    }

    mutating func render(_ events: [Event]) throws -> String {
      for event in events {
        switch event {
        case let .text(value, originalIndentation):
          flushBoundary(before: value)
          try append(value, originalIndentation: originalIndentation)
          hasContent = true
        case let .boundary(boundary):
          pending = max(pending ?? boundary, boundary)
        case .lineBoundary:
          pending = max(pending ?? .newline, .newline)
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

    private mutating func flushBoundary(before value: String) {
      defer { pending = nil }
      if !hasContent {
        if startsWithLine, context.hasSourceBefore {
          text += context.lineEnding + indentation
          column = endColumn(of: indentation, startingAt: 0)
        } else {
          text += context.leadingWhitespace
        }
        return
      }
      guard let pending else { return }
      let boundary: Boundary =
        if pending == .soft, let width = widths.last,
        endColumn(
          of:
          value
            .prefix { !$0.isSourceLayoutNewline },
          startingAt: column + 1
        ) > width {
          .newline
        } else {
          pending
        }
      switch boundary {
      case .soft:
        text += " "
        column += 1
      case .newline, .blankLine:
        text += context.lineEnding
        if boundary == .blankLine { text += context.lineEnding }
        text += indentation
        column = endColumn(of: indentation, startingAt: 0)
      }
    }

    private mutating func append(
      _ value: String, originalIndentation: String
    ) throws {
      let lines = value.split(
        omittingEmptySubsequences: false,
        whereSeparator: \.isSourceLayoutNewline
      )
      guard let first = lines.first else { return }
      if indentation != originalIndentation,
         lines.dropFirst().contains(where: {
           !$0.isEmpty && !$0.hasPrefix(originalIndentation)
         })
      {
        throw SourceLayoutError.inconsistentIndentation
      }
      text += first
      column = endColumn(of: first, startingAt: column)
      for line in lines.dropFirst() {
        var content = String(line)
        if !content.isEmpty, content.hasPrefix(originalIndentation) {
          content.removeFirst(originalIndentation.count)
          content = indentation + content
        }
        text += context.lineEnding + content
        column = endColumn(of: content, startingAt: 0)
      }
    }

    private func endColumn(
      of text: some StringProtocol,
      startingAt start: Int
    ) -> Int {
      text.reduce(start) { column, character in
        character == "\t"
          ? column + context.tabWidth - column
          % context
          .tabWidth : column + 1
      }
    }
  }
}

extension Character {
  fileprivate var isSourceLayoutNewline: Bool {
    self == "\n" || self == "\r" || self == "\r\n"
  }
}
