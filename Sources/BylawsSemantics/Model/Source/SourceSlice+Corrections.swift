extension SourceSlice {
  /// Returns one replacement that applies the edits within this slice.
  ///
  /// Edits must come from the same snapshot and remain within this slice.
  /// Captured layouts compose contained edits within retained elements.
  /// Other overlapping edits and insertions at the same position are rejected.
  /// An empty collection returns an unchanged replacement.
  /// - Throws: ``SourceError/differentSnapshots``,
  ///   ``SourceError/rangeOutOfBounds`` or ``SourceError/overlappingEdits``.
  ///   A contained layout can also throw ``SourceLayoutError`` or
  ///   ``SourceLayoutReplacementError`` when it cannot be rendered.
  public func replacement(applying edits: [SourceFix.Edit]) throws -> SourceFix
    .Edit
  {
    try replacement(applying: edits, layoutCandidates: [])
  }

  package func replacement(
    applying edits: [SourceFix.Edit], layoutCandidates: [SourceFix.Edit]
  ) throws -> SourceFix.Edit {
    for edit in edits {
      guard edit.source.snapshot == snapshot
      else { throw SourceError.differentSnapshots }
      let bounds = edit.source.range
      guard bounds.lowerBound >= range.lowerBound,
            bounds.upperBound <= range.upperBound
      else { throw SourceError.rangeOutOfBounds }
    }
    if layoutCandidates.isEmpty, edits.allSatisfy({ $0.layout == nil }) {
      return try rawReplacement(applying: edits)
    }
    let session = SourceLayoutComposition.Session(snapshot: snapshot)
    let ordered = try session.compose(
      edits: edits,
      candidates: layoutCandidates
    )
    let context = SourceLayoutReplacement.Context(
      snapshot: snapshot, bytes: session.bytes, excluding: range
    )
    return try replacement(with: session.content(
      self, applying: ordered,
      at: SourceLayoutRenderer.Placement(
        column: context.column(before: range.lowerBound),
        indentation: context.indentation(before: range.lowerBound),
        lineIndentation: context.indentation(before: range.lowerBound)
      ),
      followedBy: .init(text: SourceLayoutText.lineSuffix(after: self))
    ))
  }

  private func rawReplacement(applying edits: [SourceFix.Edit]) throws
    -> SourceFix.Edit
  {
    guard !edits.isEmpty else { return replacement(with: text) }
    let ordered = edits.sorted {
      if $0.source.range.lowerBound != $1.source.range.lowerBound {
        return $0.source.range.lowerBound < $1.source.range.lowerBound
      }
      return $0.source.range.upperBound > $1.source.range.upperBound
    }
    let original = Array(text.utf8)
    var result: [UInt8] = []
    result.reserveCapacity(original.count)
    var cursor = 0
    var previous: Range<Int>?
    for edit in ordered {
      let bounds = edit.source.range
      if let previous {
        guard previous.upperBound <= bounds.lowerBound,
              previous.lowerBound != bounds.lowerBound
        else { throw SourceError.overlappingEdits }
      }
      let lower = bounds.lowerBound - range.lowerBound
      result.append(contentsOf: original[cursor..<lower])
      result.append(contentsOf: edit.replacement.utf8)
      cursor = bounds.upperBound - range.lowerBound
      previous = bounds
    }
    result.append(contentsOf: original[cursor...])
    return replacement(with: String(decoding: result, as: UTF8.self))
  }
}
