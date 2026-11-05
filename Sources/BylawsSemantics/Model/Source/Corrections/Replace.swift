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
}
