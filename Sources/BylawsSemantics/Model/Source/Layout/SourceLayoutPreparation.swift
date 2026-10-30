import BylawsSyntax

extension SourceLayoutReplacement {
  static func prepare(
    elements: [any SourceProviding], layout: SourceLayout,
    parsedTree: SourceFileSyntax?, allowsPartialList: Bool = false,
    sourceContext: Context? = nil, baseIndentation: String? = nil,
    nested: [SourceFix.Edit] = [],
    children: [SourceLayoutComposition.Session.ComposedEdit] = [],
    session: SourceLayoutComposition.Session? = nil,
    whenLineExceeds maximumWidth: Int? = nil,
    lineEnding: String? = nil
  ) throws -> SourceLayoutPrepared {
    if let maximumWidth, maximumWidth <= 0 {
      throw SourceLayoutError.widthMustBePositive
    }
    let slices = try elements.map { try $0.source }
    guard let first = slices.first
    else { throw SourceLayoutReplacementError.emptyCollection }
    guard slices.allSatisfy({ $0.snapshot == first.snapshot }) else {
      throw SourceLayoutReplacementError.differentSnapshots
    }
    let tree = parsedTree ?? first.snapshot.syntaxTree()
    let bytes = sourceContext?.bytes ?? session?.bytes ?? first.snapshot
      .syntaxContext?.bytes ?? Array(first.snapshot.text.utf8)
    let items = try slices.map { try Item(source: $0, tree: tree) }
    let sourceList = try List(
      items: items,
      snapshot: first.snapshot,
      allowsPartialList: allowsPartialList,
      sourceBytes: bytes
    )
    let sourceContext = sourceContext ?? Context(
      snapshot: first.snapshot, bytes: bytes, excluding: sourceList.range,
      lineEnding: lineEnding
    )
    var itemsByRange: [Range<Int>: Item] = [:]
    itemsByRange.reserveCapacity(items.count)
    for item in items {
      if itemsByRange.updateValue(item, forKey: item.source.range) != nil {
        throw SourceLayoutReplacementError.repeatedElement
      }
    }
    let edits = layout.edits
    let output = try layout.sources.map { provider -> Item in
      let slice = try provider.source
      guard slice.snapshot == first.snapshot else {
        throw SourceLayoutReplacementError.differentSnapshots
      }
      if let item = itemsByRange[slice.range] {
        return item
      }
      if edits.contains(where: { $0.source == slice }),
         let item =
         items
           .first(where: { $0.contentRange.contains(slice.range) })
      {
        return item
      }
      throw SourceLayoutReplacementError.foreignElement
    }
    let identifiers = output.map(\.node.id)
    guard Set(identifiers).count == identifiers.count else {
      throw SourceLayoutReplacementError.repeatedElement
    }
    guard Set(identifiers) == Set(items.map(\.node.id)) else {
      throw SourceLayoutReplacementError.missingElement
    }
    let ending = sourceContext.lineEnding
    let leadingWhitespace = try SourceSlice(
      snapshot: first.snapshot,
      range: sourceList.range.lowerBound..<sourceList.leadingContentStart
    ).text
    let trailingWhitespace = try SourceSlice(
      snapshot: first.snapshot,
      range: sourceList.trailingContentEnd..<sourceList.range.upperBound
    ).text
    let originalIndent = sourceContext.indentation(
      before: sourceList.leadingContentStart
    )
    let ownerIndent = sourceContext.indentation(
      before: sourceList.ownerStart ?? sourceList.range.lowerBound
    )
    let unit = sourceContext.indentationUnit
    let inferredIndent = switch sourceList.indentationBase {
    case .owner: ownerIndent
    case .contents: ownerIndent + unit
    case nil:
      if sourceList.isDelimited {
        ownerIndent + unit
      } else {
        originalIndent
      }
    }
    let contentIndent = baseIndentation ?? inferredIndent
    let closingIndent =
      if sourceList.closesOwner {
        ownerIndent
      } else if let next = sourceList.nextContentStart,
                trailingWhitespace.contains(where: \.isPhysicalLayoutLineEnding)
      {
        sourceContext.indentation(before: next)
      } else {
        contentIndent
      }
    let context = SourceLayoutRenderer.Context(
      initialColumn: sourceContext
        .column(before: sourceList.leadingContentStart),
      initialIndentation: originalIndent,
      baseIndentation: contentIndent,
      indentationUnit: unit,
      lineEnding: ending,
      defaultSeparator: sourceList.isVertical ? .newline : .space,
      leadingWhitespace: leadingWhitespace,
      trailingWhitespace: trailingWhitespace,
      hasSourceBefore: sourceList.range.lowerBound > 0,
      hasSourceAfter: sourceList.nextContentStart != nil,
      closingIndentation: closingIndent
    )
    let source = try SourceSlice(
      snapshot: first.snapshot,
      range: sourceList.range
    )
    let plan = try SourceLayoutPlan(
      elements: slices.map(\.range),
      node: SourceLayoutPlan.freeze(layout, snapshot: first.snapshot),
      allowsPartialList: allowsPartialList,
      baseIndentation: baseIndentation, targetRange: source.range,
      lineWidthLimit: maximumWidth,
      nested: nested.map(SourceLayoutPlan.CapturedEdit.init)
    )
    try plan.validate(source: source)
    let session = session ?? SourceLayoutComposition.Session(
      snapshot: first.snapshot,
      tree: tree
    )
    let content = try session.prepareContent(
      source,
      applying: nested,
      adding: children
    )
    let lookaheadText = if edits.isEmpty {
      content.baseline
    } else {
      try source.replacement(applying: session.contentEdits(
        in: edits + nested + children.flatMap(\.flattenedEdits)
      )).replacement
    }
    let lastID = output.last?.node.id
    func event(for item: Item, edit: SourceFix.Edit? = nil) throws
      -> SourceLayoutDocument.Event
    {
      let source = try SourceSlice(
        snapshot: first.snapshot, range: item.contentRange
      )
      let edits = nested.filter { item.contentRange.contains($0.source.range) }
        + (edit.map { [$0] } ?? [])
      let attached = children.filter {
        item.contentRange.contains($0.edit.source.range)
      }
      let separator = sourceList.hasCommas
        && (item.node.id != lastID || sourceList.hasTrailingComma) ? "," : ""
      if edits.isEmpty, attached.isEmpty {
        let text = source.text
        if !text.contains(where: SourceLayoutText.isNewline) {
          return .text(text + separator)
        }
      }
      let content = try session.prepareContent(
        source, applying: edits, adding: attached
      )
      return .element(
        content,
        separator: separator
      )
    }
    let document = try SourceLayoutDocument(
      layout.node, separator: context.defaultSeparator,
      source: { provider in
        let slice = try provider.source
        guard let item = itemsByRange[slice.range] else {
          throw SourceLayoutReplacementError.foreignElement
        }
        return try event(for: item)
      },
      edit: { edit in
        guard let item = items.first(where: {
          $0.contentRange.contains(edit.source.range)
        }) else { throw SourceLayoutReplacementError.foreignElement }
        return try event(for: item, edit: edit)
      }
    )
    let originalColumn = source.range.lowerBound == sourceList
      .leadingContentStart ? context.initialColumn : sourceContext
      .column(before: source.range.lowerBound)
    return SourceLayoutPrepared(
      source: source, capture: plan, content: content,
      lookaheadText: lookaheadText, document: document,
      context: context,
      originalPlacement: .init(
        column: originalColumn,
        indentation: content.originalIndentation,
        lineIndentation: content.originalIndentation
      ),
      indentsContents: sourceList.indentationBase == .contents
        || sourceList.indentationBase == nil && sourceList.isDelimited,
      closesOwner: sourceList.closesOwner,
      hasBaseIndentation: baseIndentation != nil
    )
  }
}

extension Range<Int> {
  fileprivate func contains(_ other: Self) -> Bool {
    lowerBound <= other.lowerBound && upperBound >= other.upperBound
  }
}

extension Character {
  fileprivate var isPhysicalLayoutLineEnding: Bool {
    SourceLayoutText.isNewline(self)
  }
}
