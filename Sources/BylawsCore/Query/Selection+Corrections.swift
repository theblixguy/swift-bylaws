public import BylawsSemantics

extension Selection {
  /// Returns violations for elements whose proposed corrections change their source.
  ///
  /// The closure runs once per selected element. An empty result or an edit
  /// with unchanged bytes produces no violation. The source files stay unchanged.
  public func violations(
    _ requirement: String,
    @ArrayBuilder<SourceFix.Edit> changes: (Element) async throws
      -> [SourceFix.Edit]
  ) async throws -> Violations<Element> {
    var offenders: [Element] = []
    var fixes: [SourceFix?] = []
    var candidates: [SourceFix.Edit] = []
    for element in self {
      try Task.checkCancellation()
      let fix = SourceFix(proposedEdits: try await changes(element))
      guard !fix.edits.isEmpty else {
        candidates.append(contentsOf: fix.layoutCandidates)
        continue
      }
      offenders.append(element)
      fixes.append(fix)
    }
    return Violations(
      rule: requirement,
      offenders: offenders,
      checkedCount: count,
      witnesses: Array(repeating: nil, count: offenders.count),
      fixes: fixes,
      codebase: codebase,
      layoutCandidates: candidates
    )
  }
}

extension ArrayBuilder where Element == SourceFix.Edit {
  /// Includes all edits from a proposed correction.
  public static func buildExpression(_ fix: SourceFix) -> [SourceFix.Edit] {
    fix.edits + fix.layoutCandidates
  }
}
