extension Violations {
  package var hasCorrections: Bool {
    !layoutCandidates.isEmpty || proposedFixes != nil
  }

  package func removingCorrections() -> Self {
    guard hasCorrections else { return self }
    return Self(
      rule: rule, offenders: offenders, checkedCount: checkedCount,
      witnesses: witnesses, codebase: codebase
    )
  }
}

extension Rule.Findings {
  package func removingCorrections() -> Self {
    guard checks.contains(where: \.hasCorrections) else { return self }
    return Self(
      checks: checks.map { $0.removingCorrections() }, warnings: warnings
    )
  }
}
