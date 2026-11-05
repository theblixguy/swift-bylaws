extension Layout {
  /// Arranges each contained source list when this layout applies.
  ///
  /// Each list must use the same captured source and remain inside one retained
  /// element. The closure runs for each list, including empty lists and lists
  /// whose containing layout does not match its condition at its current position.
  public func applying<Sources: Collection>(
    toEach lists: some Sequence<Sources>,
    @LayoutBuilder<Sources.Element> _ content: (Sources) throws
      -> LayoutContent<Sources.Element>
  ) throws -> Self where Sources.Element: SourceProviding {
    let changes = try lists.map { elements in
      try Layout<Sources.Element>(elements, layout: content(elements))
        .correction
    }
    return try applying(SourceCorrection(combining: changes))
  }

  /// Includes contained corrections when this layout applies.
  ///
  /// Each correction must use the same captured source and remain inside one
  /// retained element. A layout without retained elements produces no correction.
  /// Otherwise, unavailable and undetermined corrections remain in the result
  /// even when the layout's condition does not match at its current position.
  public func applying(_ changes: some SourceCorrectionProviding) throws
    -> Self
  {
    try Self(correction: correction
      .applyingLayoutCorrections(changes.correction))
  }
}

extension SourceCorrection {
  package func applyingLayoutCorrections(_ changes: SourceCorrection) throws
    -> Self
  {
    if outcome == .notApplicable { return self }
    if let fix, fix.edits.isEmpty, fix.layoutCandidates.isEmpty { return self }
    if outcome == .satisfied, fix == nil { return self }
    let combined = Self(combining: [self, changes])
    guard combined.fix != nil else { return combined }
    guard let fix, let changes = changes.fix else { return self }
    let parents = fix.edits + fix.layoutCandidates
    let children = changes.edits + changes.layoutCandidates
    guard !children.isEmpty else { return self }
    let edits = try SourceLayoutComposition.attaching(children, to: parents)
    return Self(SourceFix(fix.title, proposedEdits: edits))
  }
}
