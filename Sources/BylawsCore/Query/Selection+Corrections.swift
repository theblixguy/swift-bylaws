public import BylawsSemantics

extension Selection {
  /// Returns violations from the selected elements' correction results.
  ///
  /// The closure runs once per selected element. An empty result or an edit
  /// with unchanged bytes produces no violation. An unavailable correction
  /// records a violation and its reason. Undetermined applicability throws
  /// ``/BylawsSemantics/SourceCorrectionError/undetermined(_:)``.
  /// The source files stay unchanged.
  /// Ordinary CLI checks evaluate the closure but omit corrections from
  /// the result.
  public func violations(
    _ requirement: String,
    @SourceCorrectionBuilder changes: (Element) async throws
      -> some SourceCorrectionProviding
  ) async throws -> Violations<Element> {
    var offenders: [Element] = []
    var fixes: [SourceFix?] = []
    var candidates: [SourceFix.Edit] = []
    var failures: [String?] = []
    let proposesCorrections = RuleRunPurpose.current == .proposeCorrections
    for element in self {
      try Task.checkCancellation()
      let correction = try await changes(element).correction
      guard correction.outcome != .undetermined else {
        throw SourceCorrectionError.undetermined(
          correction.reason ?? "Restrict the rule to source with a known context."
        )
      }
      guard correction.outcome == .violation else {
        if proposesCorrections, let fix = correction.fixOmittingUnchangedEdits {
          candidates.append(contentsOf: fix.layoutCandidates)
        }
        continue
      }
      offenders.append(element)
      failures.append(correction.reason)
      if proposesCorrections {
        fixes.append(correction.fixOmittingUnchangedEdits)
      }
    }
    return Violations(
      rule: requirement,
      offenders: offenders,
      checkedCount: count,
      witnesses: Array(repeating: nil, count: offenders.count),
      fixes: proposesCorrections ? fixes : nil,
      codebase: codebase,
      layoutCandidates: candidates,
      correctionFailures: failures
    )
  }
}
