extension Rule {
  /// The findings and selection steps from one run of a rule.
  public struct Inspection: Sendable {
    /// The rule's violations and warnings before baseline filtering.
    public let findings: Findings
    /// The selection steps recorded while the rule ran.
    public let selections: [SelectionInspection]
  }

  /// Runs the rule and records its Bylaws selection queries and filters.
  ///
  /// Each step lists the files or declarations it keeps and those it removes
  /// from the previous selection. Codebase include and exclude globs apply
  /// before the first step. Standard library collection operations, such as
  /// `Array.filter`, are not recorded.
  ///
  /// Inspection evaluates the rule once and retains descriptions and locations
  /// for each step. Use ``findings()`` when these details are not needed.
  public func inspect() async throws(RuleError) -> Inspection {
    let (result, selections) = await QueryInspection.collecting {
      await Result(catching: findings)
    }
    return try Inspection(findings: result.get(), selections: selections)
  }
}
