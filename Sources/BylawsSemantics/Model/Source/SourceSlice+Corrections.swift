extension SourceSlice {
  /// Returns one replacement that applies the edits within this slice.
  ///
  /// Edits must come from the same snapshot and remain within this slice.
  /// Overlapping edits and insertions at the same position are rejected.
  /// An empty collection returns an unchanged replacement.
  /// - Throws: ``SourceError/differentSnapshots``,
  ///   ``SourceError/rangeOutOfBounds`` or ``SourceError/overlappingEdits``.
  public func replacement(applying edits: [SourceFix.Edit]) throws -> SourceFix
    .Edit
  {
    let ordered = edits
      .sorted { $0.source.range.lowerBound < $1.source.range.lowerBound }
    for (index, edit) in ordered.enumerated() {
      guard edit.source.snapshot == snapshot
      else { throw SourceError.differentSnapshots }
      let bounds = edit.source.range
      guard bounds.lowerBound >= range.lowerBound,
            bounds.upperBound <= range.upperBound
      else { throw SourceError.rangeOutOfBounds }
      if index > 0 {
        let previous = ordered[index - 1].source.range
        guard previous.upperBound <= bounds.lowerBound,
              previous.lowerBound != bounds.lowerBound
        else { throw SourceError.overlappingEdits }
      }
    }
    var bytes = Array(text.utf8)
    for edit in ordered.reversed() {
      let lower = edit.source.range.lowerBound - range.lowerBound
      let upper = edit.source.range.upperBound - range.lowerBound
      bytes.replaceSubrange(lower..<upper, with: edit.replacement.utf8)
    }
    return replacement(with: String(decoding: bytes, as: UTF8.self))
  }
}
