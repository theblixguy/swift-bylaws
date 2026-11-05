/// A grouping or spacing policy that cannot produce one source correction.
public enum SourceListLayoutError: Error, Sendable, Equatable,
  CustomStringConvertible
{
  /// Explicit source emission and automatic policies occur in the same layout.
  case mixedContent
  /// A list separator is neither a newline nor a blank line.
  case unsupportedSeparator
  /// Conditional separators request different whitespace for one gap.
  case conflictingSeparators

  /// The policy constraint and the action that permits a correction.
  public var description: String {
    switch self {
    case .mixedContent:
      "Layout must use explicit source or automatic policies. Use one form for each list."
    case .unsupportedSeparator:
      "Layout must use a newline or blank line between groups. Use .newline or .blankLine."
    case .conflictingSeparators:
      "Layout must use one separator for each gap. Remove the conflicting separator conditions."
    }
  }
}
