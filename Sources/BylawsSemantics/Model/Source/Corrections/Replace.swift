/// A replacement for selected source.
public struct Replace: SourceCorrectionProviding, Sendable {
  /// The proposed correction.
  public let correction: SourceCorrection

  /// Replaces selected source with exact text.
  public init(_ target: some SourceProviding, with text: String) throws {
    correction =
      try SourceCorrection(edits: [target.source.replacement(with: text)])
  }

  /// Replaces selected whitespace with the requested spacing.
  public init(_ target: SourceSlice, with whitespace: SourceWhitespace) throws {
    correction =
      try SourceCorrection(edits: [target.replacement(with: whitespace)])
  }

  /// Retains captured syntax from inside the selected source.
  ///
  /// The rule determines whether removing the surrounding code is appropriate.
  /// The replacement preserves expression grouping and rejects comments that
  /// would be discarded.
  public init(
    _ target: some SourceProviding,
    with retained: some SourceProviding
  )
    throws
  {
    try self.init(target, with: SourceReplacement { retained })
  }

  /// Replaces source with a captured replacement description.
  public init(
    _ target: some SourceProviding,
    with replacement: SourceReplacement
  )
    throws
  {
    do {
      correction = try SourceCorrection(edits: [
        target.source.replacement(with: replacement),
      ])
    } catch let error as SourceReplacementError {
      correction = .unavailable(error.description)
    } catch let error as SourceLayoutError {
      correction = .unavailable(error.description)
    }
  }

  /// Describes captured syntax to retain in the replacement.
  public init(
    _ target: some SourceProviding,
    @SourceReplacementBuilder _ content: () throws -> SourceReplacement
  ) throws {
    try self.init(target, with: content())
  }
}

/// Why captured syntax cannot be used in a replacement.
public enum SourceReplacementError: Error, Sendable, Equatable,
  CustomStringConvertible
{
  /// A retained value does not identify a supported complete syntax node.
  case unsupportedSyntax
  /// The replacement would discard a comment or formatting directive.
  case discardedTrivia
  /// A replacement would change a multiline literal's indentation.
  case multilineLiteral
  /// The replacement does not form valid Swift in its destination.
  case syntaxChanged

  /// The reason the replacement cannot be prepared.
  public var description: String {
    switch self {
    case .unsupportedSyntax:
      "SourceReplacement must retain complete syntax nodes inside its target."
    case .discardedTrivia:
      "SourceReplacement cannot discard comments or formatting directives. Retain the source that owns them."
    case .multilineLiteral:
      "SourceReplacement cannot adjust a multiline literal. Use an explicit text replacement after checking its value."
    case .syntaxChanged:
      "SourceReplacement cannot parse at its destination. Select syntax that fits the target."
    }
  }
}
