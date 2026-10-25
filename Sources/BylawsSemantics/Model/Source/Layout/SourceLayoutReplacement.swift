import BylawsSyntax

extension Collection where Element: SourceProviding {
  /// Returns a layout replacement for a contiguous source list.
  ///
  /// The collection must be nonempty and come from one snapshot of a file.
  /// It can contain attributes, modifiers, members, statements, call arguments,
  /// parameters, enum case elements or array and dictionary elements.
  /// The `elements` projection also supports conditions, generic clauses,
  /// inherited types, tuples, closure signatures, accessors and switch cases.
  /// Attribute, modifier and comma-separated lists must be complete. Member
  /// and statement lists can be consecutive regions within a larger list.
  ///
  /// The layout must emit every input element exactly once. A replacement
  /// retains each input element and regenerates list separators. An embedded
  /// edit can change part of one element. Comments with
  /// unclear ownership and conditional-compilation boundaries stop the fix.
  /// Space indentation comes from source outside the replaced list, with two
  /// spaces used when none can be inferred. Tabs use one tab per level.
  /// Wrapping defaults to 100 characters.
  /// A non-nil `whenLineExceeds` value must be positive. The layout applies
  /// when a complete source line touched by the list exceeds that width.
  /// With `nil`, it applies unconditionally. A nested layout uses its new
  /// position in the containing layout for the width check.
  /// - Throws: ``SourceError`` when captured source cannot be read,
  ///   ``SourceLayoutReplacementError`` for unsupported input or source
  ///   ownership, or ``SourceLayoutError`` for a layout that cannot be rendered.
  ///   Errors from `layout` also propagate to the caller.
  public func replacement(
    whenLineExceeds maximumWidth: Int? = nil,
    @SourceLayoutBuilder _ layout: () throws -> SourceLayout
  ) throws -> SourceFix.Edit {
    try SourceLayoutReplacement.make(
      elements: map(\.self), layout: layout(), whenLineExceeds: maximumWidth
    )
  }
}

package enum SourceLayoutReplacement {
  package static func make(
    elements: [any SourceProviding], layout: SourceLayout,
    whenLineExceeds maximumWidth: Int? = nil
  ) throws -> SourceFix.Edit {
    try make(
      elements: elements, layout: layout, parsedTree: nil,
      whenLineExceeds: maximumWidth
    )
  }

  static func make(
    elements: [any SourceProviding], layout: SourceLayout,
    parsedTree: SourceFileSyntax?, allowsPartialList: Bool = false,
    sourceContext: Context? = nil, baseIndentation: String? = nil,
    nested: [SourceFix.Edit] = [],
    placement: SourceLayoutRenderer.Placement? = nil,
    whenLineExceeds maximumWidth: Int? = nil,
    lineEnding: String? = nil
  ) throws -> SourceFix.Edit {
    if let maximumWidth, maximumWidth <= 0 {
      throw SourceLayoutError.widthMustBePositive
    }
    let slices = try elements.map { try $0.source }
    guard let first = slices.first
    else { throw SourceLayoutReplacementError.emptyCollection }
    guard slices.allSatisfy({ $0.snapshot == first.snapshot }) else {
      throw SourceLayoutReplacementError.differentSnapshots
    }
    let tree = parsedTree ?? first.snapshot.parsedTree
      ?? first.snapshot.swiftLanguageMode.parse(first.snapshot.text)
    let bytes = sourceContext?.bytes ?? first.snapshot.syntaxContext?.bytes
      ?? Array(first.snapshot.text.utf8)
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
    var context = SourceLayoutRenderer.Context(
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
    let session = SourceLayoutComposition.Session(
      snapshot: first.snapshot,
      tree: tree
    )
    if let placement {
      context = projectedContext(
        context, at: placement, source: source, list: sourceList,
        hasBaseIndentation: baseIndentation != nil
      )
    }
    if let maximumWidth {
      let unchangedPlacement = SourceLayoutRenderer.Placement(
        column: placement?.column ?? sourceContext
          .column(before: source.range.lowerBound),
        indentation: placement?.lineIndentation
          ?? sourceContext.indentation(before: source.range.lowerBound),
        lineIndentation: placement?.lineIndentation
          ?? sourceContext.indentation(before: source.range.lowerBound),
        trailingText: placement?.trailingText ?? SourceLayoutText
          .lineSuffix(after: source)
      )
      let contentEdits = try session.contentEdits(in: nested)
      let measuredText = try session.content(
        source,
        applying: contentEdits,
        at: unchangedPlacement
      )
      if !exceedsLineWidth(
        maximumWidth, source: source, renderedText: measuredText,
        at: placement, startingColumn: unchangedPlacement.column,
        hasNestedEdits: !contentEdits.isEmpty
      ) {
        return SourceFix.Edit(
          source: source,
          replacement: try session.content(
            source,
            applying: nested,
            at: unchangedPlacement
          ),
          layout: plan
        )
      }
    }
    let lastID = output.last?.node.id
    func render(
      _ item: Item,
      edit: SourceFix.Edit? = nil,
      at placement: SourceLayoutRenderer.Placement
    ) throws -> String {
      let content = try SourceSlice(
        snapshot: first.snapshot,
        range: item.contentRange
      )
      let children = nested
        .filter { item.contentRange.contains($0.source.range) }
        + (edit.map { [$0] } ?? [])
      let separator = sourceList.hasCommas
        && (item.node.id != lastID || sourceList.hasTrailingComma) ? "," : ""
      var placement = placement
      placement.trailingText = separator
      return try session
        .content(content, applying: children, at: placement) + separator
    }
    let replacement = try SourceLayoutRenderer.render(
      layout,
      context: context,
      resolve: { provider, placement in
        let slice = try provider.source
        guard let item = itemsByRange[slice.range] else {
          throw SourceLayoutReplacementError.foreignElement
        }
        return try render(item, at: placement)
      },
      resolveEdit: { edit, placement in
        guard let item = items
          .first(where: { $0.contentRange.contains(edit.source.range) })
        else {
          throw SourceLayoutReplacementError.foreignElement
        }
        return try render(item, edit: edit, at: placement)
      }
    )
    return SourceFix.Edit(
      source: source, replacement: replacement, layout: plan
    )
  }

  private static func projectedContext(
    _ originalContext: SourceLayoutRenderer.Context,
    at placement: SourceLayoutRenderer.Placement,
    source: SourceSlice, list sourceList: List,
    hasBaseIndentation: Bool
  ) -> SourceLayoutRenderer.Context {
    var context = originalContext
    let unit = context.indentationUnit
    let original = placement.originalText ?? source.text
    let leading = String(original.prefix(while: isLayoutWhitespace))
    context.initialColumn = SourceTextWidth.column(
      after: leading, startingAt: placement.column
    )
    context.initialIndentation = leading
      .contains(where: \.isPhysicalLayoutLineEnding)
      ? SourceLayoutText
      .indentation(in: SourceLayoutText.lastLine(in: leading))
      : placement.lineIndentation
    context.baseIndentation = if hasBaseIndentation {
      placement.lineIndentation
    } else if sourceList.indentationBase == .contents
      || sourceList.indentationBase == nil && sourceList.isDelimited
    {
      placement.lineIndentation + unit
    } else { placement.lineIndentation }
    context.closingIndentation = sourceList.closesOwner
      ? placement.lineIndentation : context.baseIndentation
    context.leadingWhitespace = leading
    context.trailingWhitespace = String(original.reversed()
      .prefix(while: isLayoutWhitespace).reversed())
    return context
  }

  private static func exceedsLineWidth(
    _ maximumWidth: Int, source: SourceSlice, renderedText: String,
    at placement: SourceLayoutRenderer.Placement?, startingColumn: Int,
    hasNestedEdits: Bool
  ) -> Bool {
    if placement == nil, !hasNestedEdits {
      return source.hasLine(exceeding: maximumWidth)
    }
    guard !renderedText.isEmpty else { return false }
    let measured = if renderedText.last?.isPhysicalLayoutLineEnding == true {
      renderedText
    } else {
      renderedText + (placement?.trailingText ?? SourceLayoutText
        .lineSuffix(after: source))
    }
    let lines = measured.split(
      omittingEmptySubsequences: false,
      whereSeparator: \.isPhysicalLayoutLineEnding
    )
    return lines.enumerated().contains { index, line in
      SourceTextWidth.exceeds(
        maximumWidth, in: line, startingAt: index == 0 ? startingColumn : 0
      )
    }
  }

  private static func isLayoutWhitespace(_ character: Character) -> Bool {
    character == " " || character == "\t" || character
      .isPhysicalLayoutLineEnding
  }
}

extension Range<Int> {
  fileprivate func contains(_ other: Self) -> Bool {
    lowerBound <= other.lowerBound && upperBound >= other.upperBound
  }
}

extension Character {
  fileprivate var isPhysicalLayoutLineEnding: Bool {
    self == "\n" || self == "\r" || self == "\r\n"
  }
}
