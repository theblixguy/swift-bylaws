package enum SourceLayoutRenderer {
  package struct Placement {
    package let column: Int
    package let indentation: String
    package let lineIndentation: String
    package var originalText: String?
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

  package static func render(_ layout: SourceLayout, context: Context) throws
    -> String
  {
    guard context.defaultWidth > 0
    else { throw SourceLayoutError.widthMustBePositive }
    func content(_ source: SourceSlice, edit: SourceFix.Edit? = nil)
      -> SourceLayoutDocument
    {
      let changes: [SourceLayoutContent.Change] = edit.map {
        [.init(range: $0.source.range, value: .text($0.replacement))]
      } ?? []
      let content = SourceLayoutContent(
        source: source,
        originalIndentation: SourceLayoutText.indentation(
          in: Array(source.snapshot.text.utf8), before: source.range.lowerBound
        ),
        baseline: edit?.replacement ?? source.text, changes: changes
      )
      return SourceLayoutDocument(events: [.content(content)])
    }
    let document = try SourceLayoutDocument(
      layout.node, separator: context.defaultSeparator,
      source: { try content($0.source) },
      edit: { content($0.source, edit: $0) }
    )
    guard !layout.sources.isEmpty else { return "" }
    return try render(document, context: context)
  }

  static func render(
    _ document: SourceLayoutDocument, context: Context,
    followedBy following: SourceLayoutContinuation = .end
  ) throws -> String {
    guard context.defaultWidth > 0
    else { throw SourceLayoutError.widthMustBePositive }
    var writer = Writer(context: context)
    return try writer.render(document.events, followedBy: following)
  }

  static func render(
    _ document: SourceLayoutDocument, at placement: Placement,
    followedBy following: SourceLayoutContinuation,
    tabWidth: Int = 8
  ) throws -> String {
    try render(
      document,
      context: Context(
        initialColumn: placement.column,
        initialIndentation: placement.lineIndentation,
        baseIndentation: placement.indentation,
        tabWidth: tabWidth
      ),
      followedBy: following
    )
  }

  static func render(
    _ prepared: SourceLayoutPrepared, at placement: Placement? = nil,
    followedBy following: SourceLayoutContinuation? = nil,
    tabWidth: Int = 8
  ) throws -> String {
    let position = placement ?? prepared.originalPlacement
    let following = following ?? .init(text: SourceLayoutText.lineSuffix(
      after: prepared.source
    ))
    let unchanged = Placement(
      column: position.column, indentation: position.lineIndentation,
      lineIndentation: position.lineIndentation,
      originalText: position.originalText
    )
    let useOriginal: Bool
    if let maximumWidth = prepared.maximumWidth {
      let text = try prepared.content.measuredText(
        indentation: unchanged.indentation
      )
      useOriginal = !exceeds(
        maximumWidth, text: text, startingAt: unchanged.column,
        followedBy: following, tabWidth: tabWidth
      )
    } else { useOriginal = false }
    let result: String
    if useOriginal {
      result = try render(
        SourceLayoutDocument(events: [.content(prepared.content)]),
        at: unchanged, followedBy: following, tabWidth: tabWidth
      )
    } else {
      var context = placement.map {
        prepared.projectedContext(at: $0, tabWidth: tabWidth)
      } ?? prepared.context
      context.tabWidth = tabWidth
      result = try render(
        prepared.document,
        context: context,
        followedBy: following
      )
    }
    return prepared.trimmed ? SourceLayoutPrepared.trim(result) : result
  }

  private static func exceeds(
    _ maximumWidth: Int, text: String, startingAt column: Int,
    followedBy following: SourceLayoutContinuation, tabWidth: Int
  ) -> Bool {
    guard !text.isEmpty else { return false }
    let text = text.last.map(SourceLayoutText.isNewline) == true
      ? text : text + following.firstLine()
    return text.split(
      omittingEmptySubsequences: false,
      whereSeparator: SourceLayoutText.isNewline
    )
    .enumerated().contains { index, line in
      SourceTextWidth.exceeds(
        maximumWidth, in: line, startingAt: index == 0 ? column : 0,
        tabWidth: tabWidth
      )
    }
  }

  typealias Boundary = SourceLayoutDocument.Boundary
  typealias Event = SourceLayoutDocument.Event

  static func resolve(
    _ event: Event, at placement: Placement,
    followedBy following: SourceLayoutContinuation, tabWidth: Int
  ) throws -> String {
    switch event {
    case let .text(text): return text
    case let .content(content):
      return try render(
        content.document(indentation: placement.indentation),
        at: placement,
        followedBy: following,
        tabWidth: tabWidth
      )
    case let .element(content, separator):
      var document = try content.document(indentation: placement.indentation)
      document = SourceLayoutDocument(events: document
        .events + [.text(separator)])
      return try render(
        document,
        at: placement,
        followedBy: following,
        tabWidth: tabWidth
      )
    case let .layout(layout, originalText):
      var position = placement
      position.originalText = originalText
      return try render(
        layout,
        at: position,
        followedBy: following,
        tabWidth: tabWidth
      )
    case .line, .boundary, .lineBoundary, .indent, .align, .endIndentation,
         .wrap, .endWrap: throw SourceError.syntaxMismatch
    }
  }
}
