/// A named set of files for a dependency-cycle check.
public struct DependencyGroup: Sendable, Hashable {
  /// The name shown in cycle reports.
  public let name: String
  /// File globs relative to the codebase root.
  public let files: [String]

  /// Creates a group from file globs relative to the codebase root.
  ///
  /// Groups in one check must have distinct, non-empty names. A selected file
  /// can match several patterns in one group, but cannot belong to two groups.
  public init(_ name: String, files: [String]) {
    self.name = name
    self.files = files
  }
}
