import BylawsSyntax

extension Collection where Element: SourceProviding {
  /// Returns a layout replacement for a contiguous source list.
  ///
  /// The collection must be nonempty and come from one snapshot of a file.
  /// It can contain attributes, modifiers, members, statements, call arguments,
  /// parameters, enum case elements or array and dictionary elements.
  /// Attribute, modifier and comma-separated lists must be complete. Member
  /// and statement lists can be consecutive regions within a larger list.
  ///
  /// The layout must emit every input element exactly once. A replacement
  /// retains each input element and regenerates list separators. An embedded
  /// edit can change part of one element. Comments with
  /// unclear ownership and conditional-compilation boundaries stop the fix.
  /// Indentation comes from the source, with two spaces used when no existing
  /// indentation can be inferred. Wrapping defaults to 100 characters.
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
    let slices = try elements.map { try $0.source }
    guard let first = slices.first
    else { throw SourceLayoutReplacementError.emptyCollection }
    guard slices.allSatisfy({ $0.snapshot == first.snapshot }) else {
      throw SourceLayoutReplacementError.differentSnapshots
    }
    let tree = first.snapshot.swiftLanguageMode.parse(first.snapshot.text)
    let items = try slices.map { try Item(source: $0, tree: tree) }
    let sourceList = try List(items: items, snapshot: first.snapshot)
    let edits = layout.edits
    let output = try layout.sources.map { provider -> Item in
      let slice = try provider.source
      guard slice.snapshot == first.snapshot else {
        throw SourceLayoutReplacementError.differentSnapshots
      }
      if let item =
        items
          .first(where: { $0.source.range == slice.range })
      {
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
    let ending = first.snapshot.lineEnding
    let leadingWhitespace = try SourceSlice(
      snapshot: first.snapshot,
      range: sourceList.range.lowerBound..<sourceList.leadingContentStart
    ).text
    let trailingWhitespace = try SourceSlice(
      snapshot: first.snapshot,
      range: sourceList.trailingContentEnd..<sourceList.range.upperBound
    ).text
    let originalIndent = indentation(
      in: first.snapshot.text,
      before: sourceList.leadingContentStart
    )
    let ownerIndent = indentation(
      in: first.snapshot.text,
      before: sourceList.ownerStart ?? sourceList.range.lowerBound
    )
    let unit = indentationUnit(in: first.snapshot.text)
    let contentIndent =
      if sourceList.isDelimited {
        ownerIndent + unit
      } else if sourceList.isVertical, sourceList.ownerStart != nil,
                !leadingWhitespace.contains(where: \.isPhysicalLayoutLineEnding)
      {
        ownerIndent + unit
      } else {
        originalIndent
      }
    let closingIndent =
      if sourceList.closesOwner {
        ownerIndent
      } else if let next = sourceList.nextContentStart,
                trailingWhitespace.contains(where: \.isPhysicalLayoutLineEnding)
      {
        indentation(in: first.snapshot.text, before: next)
      } else {
        contentIndent
      }
    let context = SourceLayoutRenderer.Context(
      initialColumn: column(
        in: first.snapshot.text,
        before: sourceList.leadingContentStart
      ),
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
        guard let item =
          items
            .first(where: { $0.source.range == slice.range })
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

  private static func column(in text: String, before offset: Int) -> Int {
    let prefix = String(decoding: text.utf8.prefix(offset), as: UTF8.self)
    let line =
      prefix.split(
        omittingEmptySubsequences: false,
        whereSeparator: \.isPhysicalLayoutLineEnding
      ).last ?? ""
    return line.reduce(0) { column, character in
      character == "\t" ? column + 8 - column % 8 : column + 1
    }
  }

  private static func indentation(
    in text: String,
    before offset: Int
  ) -> String {
    let prefix = String(decoding: text.utf8.prefix(offset), as: UTF8.self)
    let line =
      prefix.split(
        omittingEmptySubsequences: false,
        whereSeparator: \.isPhysicalLayoutLineEnding
      ).last ?? ""
    return String(line.prefix { $0 == " " || $0 == "\t" })
  }

  private static func indentationUnit(in text: String) -> String {
    let indents = text.split(whereSeparator: \.isPhysicalLayoutLineEnding).map {
      String($0.prefix { $0 == " " || $0 == "\t" })
    }.filter { !$0.isEmpty }
    if indents.contains(where: { $0.hasPrefix("\t") }) { return "\t" }
    return indents.min(by: { $0.count < $1.count }) ?? "  "
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
