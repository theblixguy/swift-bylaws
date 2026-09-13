public import BylawsSemantics

/// A check result that a rule can report as violations and warnings.
public protocol RuleResult: Sendable {
  /// Returns the complete result for reporting.
  ///
  /// - Parameter location: The position for issues without a source declaration.
  func findings(reportedAt location: DeclarationLocation) -> Rule.Findings
}

extension Violations: RuleResult where Element: Located {
  /// Returns these violations without additional warnings.
  public func findings(reportedAt location: DeclarationLocation) -> Rule
    .Findings
  {
    Rule.Findings(violations: erased())
  }
}

extension Rule.Findings: RuleResult {
  /// Returns these findings with their existing source locations.
  public func findings(reportedAt location: DeclarationLocation) -> Self {
    self
  }
}
