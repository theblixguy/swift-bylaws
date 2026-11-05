/// A correction that cannot be prepared or whose applicability is unknown.
public enum SourceCorrectionError: Error, Sendable, Equatable,
  CustomStringConvertible
{
  /// The source fails the rule, but the proposed correction cannot be prepared.
  case unavailable(String)
  /// The available source cannot establish whether the correction applies.
  case undetermined(String)

  /// The reason the correction cannot be prepared or assessed.
  public var description: String {
    switch self {
    case let .unavailable(reason): "SourceCorrection cannot prepare the correction. \(reason)"
    case let .undetermined(reason): "SourceCorrection cannot establish applicability. \(reason)"
    }
  }
}

extension SourceCorrection {
  /// Returns the prepared fix or throws when preparation was unsuccessful.
  ///
  /// A nonmatching operation or satisfied requirement can return `nil`.
  public func preparedFix() throws(SourceCorrectionError) -> SourceFix? {
    switch outcome {
    case .notApplicable, .satisfied: fix
    case .violation:
      if let fix { fix }
      else { throw .unavailable(reason ?? "Select another correction.") }
    case .undetermined:
      throw .undetermined(reason ??
        "Restrict the rule to source with a known context.")
    }
  }
}
