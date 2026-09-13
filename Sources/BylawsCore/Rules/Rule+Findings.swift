extension Rule {
  /// The check results and warnings from one run of a rule.
  public struct Findings: Sendable {
    /// The individual check results, in execution order.
    public let checks: [Violations<Offender>]

    /// The warnings reported during the rule's run.
    public let warnings: [Warning]

    /// The combined violations, including each failed check's requirement.
    ///
    /// The checked count is the sum of the individual check counts, including
    /// elements checked more than once. Computing this value takes time
    /// proportional to the number of checks and offenders.
    public var violations: Violations<Offender> {
      if checks.count == 1, let check = checks.first { return check }
      return Violations(
        rule: "satisfy all checks",
        offenders: checks.flatMap { check in
          check.offenders.map { offender in
            Offender(
              description: offender.description,
              name: offender.name,
              location: offender.location,
              affectedPath: offender.affectedPath,
              requirement: offender.requirement ?? check.rule
            )
          }
        },
        checkedCount: checks.reduce(0) { $0 + $1.checkedCount }
      )
    }

    /// Creates findings from one check's violations and warnings.
    public init(violations: Violations<Offender>, warnings: [Warning] = []) {
      self.init(checks: [violations], warnings: warnings)
    }

    /// Creates findings from individual checks and their warnings.
    public init(checks: [Violations<Offender>], warnings: [Warning] = []) {
      self.checks = checks
      self.warnings = warnings
    }
  }
}
