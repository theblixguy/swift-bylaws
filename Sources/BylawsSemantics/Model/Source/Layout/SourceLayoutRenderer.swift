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
      let text = edit?.replacement ?? source.text
      if !text.contains(where: SourceLayoutText.isNewline) {
        return SourceLayoutDocument(events: [.text(text)])
      }
      let changes: [SourceLayoutContent.Change] = edit.map {
        [.init(range: $0.source.range, value: .text($0.replacement))]
      } ?? []
      let content = SourceLayoutContent(
        source: source,
        originalIndentation: SourceLayoutText.indentation(
          in: source.snapshot.syntaxContext?
            .bytes ?? Array(source.snapshot.text.utf8),
          before: source.range.lowerBound
        ),
        baseline: text, changes: changes
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
    return try render(.document(
      document, context: context, following: following, trimmed: false
    ))
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
    try render(request(
      prepared, at: placement, followedBy: following, tabWidth: tabWidth
    ))
  }

  private static func request(
    _ prepared: SourceLayoutPrepared, at placement: Placement?,
    followedBy following: SourceLayoutContinuation?, tabWidth: Int
  ) throws -> Request {
    let position = placement ?? prepared.originalPlacement
    let following = following ?? .init(text: SourceLayoutText.lineSuffix(
      after: prepared.source
    ))
    let unchanged = Placement(
      column: position.column, indentation: position.lineIndentation,
      lineIndentation: position.lineIndentation,
      originalText: position.originalText
    )
    if let maximumWidth = prepared.maximumWidth {
      let text = try prepared.content
        .measuredText(indentation: unchanged.indentation)
      if !following.exceeds(
        maximumWidth, after: text, startingAt: unchanged.column,
        tabWidth: tabWidth
      ) {
        if prepared.content.changes.isEmpty {
          return .text(prepared.trimmed ? SourceLayoutPrepared
            .trim(text) : text)
        }
        return try .document(
          prepared.content.document(indentation: unchanged.indentation),
          context: context(at: unchanged, tabWidth: tabWidth),
          following: following, trimmed: prepared.trimmed
        )
      }
    }
    var context = placement.map {
      prepared.projectedContext(at: $0, tabWidth: tabWidth)
    } ?? prepared.context
    context.tabWidth = tabWidth
    return .document(
      prepared.document, context: context, following: following,
      trimmed: prepared.trimmed
    )
  }

  private static func context(
    at placement: Placement,
    tabWidth: Int
  ) -> Context {
    Context(
      initialColumn: placement.column,
      initialIndentation: placement.lineIndentation,
      baseIndentation: placement.indentation, tabWidth: tabWidth
    )
  }

  typealias Boundary = SourceLayoutDocument.Boundary
  typealias Event = SourceLayoutDocument.Event

  static func literal(_ event: Event, indentation: String) throws -> String? {
    switch event {
    case let .text(text): text
    case let .content(content) where content.changes.isEmpty:
      try content.measuredText(indentation: indentation)
    case let .element(content, separator) where content.changes.isEmpty:
      try content.measuredText(indentation: indentation) + separator
    default: nil
    }
  }

  static func request(
    _ event: Event, at placement: Placement,
    followedBy following: SourceLayoutContinuation, tabWidth: Int
  ) throws -> Request {
    switch event {
    case let .text(text): return .text(text)
    case let .content(content):
      if content.changes.isEmpty {
        return try .text(content
          .measuredText(indentation: placement.indentation))
      }
      return try .document(
        content.document(indentation: placement.indentation),
        context: context(at: placement, tabWidth: tabWidth),
        following: following, trimmed: false
      )
    case let .element(content, separator):
      if content.changes.isEmpty {
        return try .text(content
          .measuredText(indentation: placement.indentation) + separator)
      }
      var document = try content.document(indentation: placement.indentation)
      document = SourceLayoutDocument(events: document
        .events + [.text(separator)])
      return .document(
        document, context: context(at: placement, tabWidth: tabWidth),
        following: following, trimmed: false
      )
    case let .layout(layout, originalText):
      var position = placement
      position.originalText = originalText
      return try request(
        layout, at: position, followedBy: following, tabWidth: tabWidth
      )
    case .line, .boundary, .lineBoundary, .indent, .align, .endIndentation,
         .wrap, .endWrap: throw SourceError.syntaxMismatch
    }
  }
}
