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
    for element in self {
      try Task.checkCancellation()
      let edits = try await changes(element).filter {
        !$0.source.text.utf8.elementsEqual($0.replacement.utf8)
      }
      guard !edits.isEmpty else { continue }
      offenders.append(element)
      fixes.append(SourceFix(edits: edits))
    }
    return Violations(
      rule: requirement,
      offenders: offenders,
      checkedCount: count,
      witnesses: Array(repeating: nil, count: offenders.count),
      fixes: fixes,
      codebase: codebase
    )
  }
}
