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
    let session = SourceLayoutComposition.Session(snapshot: snapshot)
    let ordered = try session.compose(
      edits: edits,
      candidates: layoutCandidates
    )
    let bytes = Array(snapshot.text.utf8)
    let context = SourceLayoutReplacement.Context(
      snapshot: snapshot, bytes: bytes, excluding: range
    )
    return try replacement(with: session.content(
      self, applying: ordered,
      at: SourceLayoutRenderer.Placement(
        column: context.column(before: range.lowerBound),
        indentation: context.indentation(before: range.lowerBound),
        lineIndentation: context.indentation(before: range.lowerBound)
      )
    ))
  }
}
