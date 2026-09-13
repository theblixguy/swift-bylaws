public import BylawsSemantics

/// Several check results reported by one rule.
///
/// Each check retains its requirement and source locations. All checks share
/// the containing rule's ID, enforcement level and baseline settings.
public struct RuleResults: RuleResult {
  let results: [any RuleResult]

  /// Combines check results of different types in the supplied order.
  public init<each Result: RuleResult>(_ results: repeat each Result) {
    var collected: [any RuleResult] = []
    for result in repeat each results { collected.append(result) }
    self.results = collected
  }

  package init(results: [any RuleResult]) {
    self.results = results
  }

  /// Returns all check results and warnings in their original order.
  ///
  /// If there are no checks or warnings, returns a warning at `location`.
  public func findings(reportedAt location: DeclarationLocation) -> Rule
    .Findings
  {
    var checks: [Violations<Offender>] = []
    var warnings: [Rule.Warning] = []
    for result in results {
      let findings = result.findings(reportedAt: location)
      checks.append(contentsOf: findings.checks)
      warnings.append(contentsOf: findings.warnings)
    }
    if checks.isEmpty, warnings.isEmpty {
      warnings.append(.init(
        message: "Rule contains no checks. Add a check or review its conditions.",
        location: location
      ))
    }
    return Rule.Findings(checks: checks, warnings: warnings)
  }
}
