public import BylawsSemantics

extension Selection {
  /// Returns violations for elements whose proposed corrections change their source.
  ///
  /// The closure runs once per selected element. An empty result or an edit
  /// with unchanged bytes produces no violation. The source files stay unchanged.
  /// Ordinary CLI checks evaluate the closure but omit corrections from
  /// the result.
  public func violations(
    _ requirement: String,
    @ArrayBuilder<SourceFix.Edit> changes: (Element) async throws
      -> [SourceFix.Edit]
  ) async throws -> Violations<Element> {
    var offenders: [Element] = []
    var fixes: [SourceFix?] = []
    var candidates: [SourceFix.Edit] = []
    let proposesCorrections = RuleRunPurpose.current == .proposeCorrections
    for element in self {
      try Task.checkCancellation()
      let edits = try await changes(element)
      if !proposesCorrections {
        if edits.contains(where: {
          !$0.source.text.utf8.elementsEqual($0.replacement.utf8)
        }) {
          offenders.append(element)
        }
        continue
      }
      let fix = SourceFix(proposedEdits: edits)
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
      fixes: proposesCorrections ? fixes : nil,
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
