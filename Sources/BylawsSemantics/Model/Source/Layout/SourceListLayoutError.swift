/// A grouping or spacing policy that cannot produce one source correction.
public enum SourceListLayoutError: Error, Sendable, Equatable,
  CustomStringConvertible
{
  /// Grouping and conditional spacing occur in the same replacement.
  case mixedPolicies
  /// Conditional separators request different whitespace for one gap.
  case conflictingSeparators

  /// The policy constraint and the action that permits a correction.
  public var description: String {
    switch self {
    case .mixedPolicies:
      "SourceListLayout must use grouping or conditional spacing in one replacement. Define separate replacements for these policies."
    case .conflictingSeparators:
      "SourceListLayout must use one separator for each gap. Remove the conflicting separator conditions."
    }
  }
}
