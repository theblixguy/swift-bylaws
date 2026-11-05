import BylawsSyntax

extension SourceSlice {
  /// Retains captured syntax from inside this slice.
  ///
  /// The replacement adjusts indentation and preserves expression grouping.
  /// Removing surrounding code can change behaviour, which the rule must assess.
  /// Comments outside the retained syntax cause the replacement to be rejected.
  public func replacement(with retained: some SourceProviding) throws
    -> SourceFix.Edit
  {
    try replacement(with: SourceReplacement { retained })
  }

  /// Replaces this slice with captured syntax and explicit scopes.
  public func replacement(with replacement: SourceReplacement) throws
    -> SourceFix.Edit
  {
    let retained = try SourceReplacementPlan(replacement, target: self)
    let ranges = retained.node.ranges
    let plan = SourceLayoutPlan(
      elements: ranges,
      targetRange: range, mode: .replacement(retained)
    )
    let session = SourceLayoutComposition.Session(snapshot: snapshot)
    let proposed = SourceFix.Edit(source: self, replacement: "", layout: plan)
    let text = try session.render(proposed)
    return SourceFix.Edit(source: self, replacement: text, layout: plan)
  }
}
