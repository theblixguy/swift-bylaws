public import BylawsSemantics

/// Combines source operations and existing edits into one correction.
@resultBuilder
public enum SourceCorrectionBuilder {
  /// Includes a correction, operation or collection of operations.
  public static func buildExpression(_ value: some SourceCorrectionProviding)
    -> SourceCorrection { value.correction }

  /// Includes an edit array, including an empty array literal.
  public static func buildExpression(_ edits: [SourceFix.Edit])
    -> SourceCorrection { edits.correction }

  /// Creates an empty correction.
  public static func buildBlock() -> SourceCorrection { .notApplicable }

  /// Starts a correction with one operation.
  public static func buildPartialBlock(first value: SourceCorrection)
    -> SourceCorrection { value }

  /// Combines operations into one correction.
  public static func buildPartialBlock(
    accumulated: SourceCorrection, next: SourceCorrection
  ) -> SourceCorrection {
    SourceCorrection(combining: [accumulated, next])
  }

  /// Includes an optional operation.
  public static func buildOptional(_ value: SourceCorrection?)
    -> SourceCorrection { value ?? .notApplicable }

  /// Includes the first branch's correction.
  public static func buildEither(first value: SourceCorrection)
    -> SourceCorrection { value }

  /// Includes the second branch's correction.
  public static func buildEither(second value: SourceCorrection)
    -> SourceCorrection { value }

  /// Includes the operations produced by a loop.
  public static func buildArray(_ values: [SourceCorrection])
    -> SourceCorrection { SourceCorrection(combining: values) }

  /// Includes a correction available on this platform.
  public static func buildLimitedAvailability(_ value: SourceCorrection)
    -> SourceCorrection { value }
}
