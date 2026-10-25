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
  /// - Throws: ``SourceError`` when captured source cannot be read,
  ///   ``SourceLayoutReplacementError`` for unsupported input or source
  ///   ownership, or ``SourceLayoutError`` for a layout that cannot be rendered.
  ///   Errors from `layout` also propagate to the caller.
  public func replacement(
    @SourceLayoutBuilder _ layout: () throws -> SourceLayout
  ) throws -> SourceFix.Edit {
    try SourceLayoutReplacement.make(elements: map(\.self), layout: layout())
  }
}

package enum SourceLayoutReplacement {
  package static func make(
    elements: [any SourceProviding], layout: SourceLayout
  ) throws -> SourceFix.Edit {
    try make(elements: elements, layout: layout, parsedTree: nil)
  }

  static func make(
    elements: [any SourceProviding], layout: SourceLayout,
    parsedTree: SourceFileSyntax?, allowsPartialList: Bool = false,
    sourceContext: Context? = nil, baseIndentation: String? = nil
  ) throws -> SourceFix.Edit {
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
      snapshot: first.snapshot, bytes: bytes, excluding: sourceList.range
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
    let lastID = output.last?.node.id
    func rendered(
      _ item: Item,
      replacing edit: SourceFix.Edit? = nil
    ) throws -> String {
      var text = try SourceSlice(
        snapshot: first.snapshot,
        range: item.contentRange
      ).text
      if let edit {
        let start = edit.source.range.lowerBound - item.contentRange.lowerBound
        let end = edit.source.range.upperBound - item.contentRange.lowerBound
        var bytes = Array(text.utf8)
        bytes.replaceSubrange(start..<end, with: edit.replacement.utf8)
        text = String(decoding: bytes, as: UTF8.self)
      }
      if sourceList.hasCommas,
         item.node.id != lastID || sourceList.hasTrailingComma
      {
        text += ","
      }
      return text
    }
    let replacement = try SourceLayoutRenderer.render(
      layout,
      context: context,
      resolve: { provider in
        let slice = try provider.source
        guard let item = itemsByRange[slice.range]
        else {
          throw SourceLayoutReplacementError.foreignElement
        }
        return try rendered(item)
      },
      resolveEdit: { edit in
        guard let item =
          items
            .first(where: { $0.contentRange.contains(edit.source.range) })
        else {
          throw SourceLayoutReplacementError.foreignElement
        }
        return try rendered(item, replacing: edit)
      }
    )
    let source = try SourceSlice(
      snapshot: first.snapshot,
      range: sourceList.range
    )
    return source.replacement(with: replacement)
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
