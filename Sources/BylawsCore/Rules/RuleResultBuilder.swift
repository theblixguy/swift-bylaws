/// Collects the check expressions in a rule body.
@resultBuilder
public enum RuleResultBuilder {
  /// Includes one check result.
  public static func buildExpression(_ result: some RuleResult)
    -> [any RuleResult] { [result] }
  /// Combines check expressions in source order.
  public static func buildBlock(_ components: [any RuleResult]...)
    -> [any RuleResult] { components.flatMap(\.self) }
  /// Includes the first branch when its condition is true.
  public static func buildEither(first component: [any RuleResult])
    -> [any RuleResult] { component }
  /// Includes the alternative branch when its condition is false.
  public static func buildEither(second component: [any RuleResult])
    -> [any RuleResult] { component }
  /// Includes an optional branch, or no checks when it is absent.
  public static func buildOptional(_ component: [any RuleResult]?)
    -> [any RuleResult] { component ?? [] }
  /// Combines checks in loop iteration order.
  public static func buildArray(_ components: [[any RuleResult]])
    -> [any RuleResult] { components.flatMap(\.self) }
  /// Includes the selected branch of an availability check.
  public static func buildLimitedAvailability(_ component: [any RuleResult])
    -> [any RuleResult] { component }
  /// Returns the collected checks as one rule result.
  public static func buildFinalResult(_ components: [any RuleResult])
    -> RuleResults { RuleResults(results: components) }
}
