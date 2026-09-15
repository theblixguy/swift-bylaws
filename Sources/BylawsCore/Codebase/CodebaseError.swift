public import BylawsSemantics
public import Foundation

/// An error from resolving or reading a codebase.
///
/// Later versions may add cases.
@nonexhaustive
public enum CodebaseError: Error, Sendable, Hashable {
  /// A path that could not be read and the reason for the failure.
  public struct ReadFailure: Sendable, Hashable {
    /// The path that could not be read.
    public let path: String

    /// The operating-system or text-decoding error.
    public let reason: String

    /// Creates a read failure for `path`.
    public init(path: String, reason: String) {
      self.path = path
      self.reason = reason
    }
  }

  /// No directory above the starting file contains a recognised project marker.
  case rootNotFound(searchedFrom: String)

  /// The configured root path is not a directory.
  case notADirectory(path: String)

  /// Project settings do not identify one supported language mode.
  case languageModeUnavailable(path: String)

  /// A Bazel graph export that cannot be read or lacks dependency data.
  case bazelGraph(path: String, reason: String)

  /// Files or directories under the root that the parse cannot read.
  ///
  /// Queries require a complete view of the codebase. Any unreadable path fails
  /// the run.
  case unreadable(failures: [ReadFailure])

  /// Files under the root that have a syntax error.
  ///
  /// The model is missing declarations from such a file and cannot prove
  /// that a rule passes. The query throws.
  case didNotParse(diagnostics: [SourceParseDiagnostic])

  /// A name-matching pattern that does not compile as a regular expression.
  case invalidRegularExpression(pattern: String)
}

extension CodebaseError: CustomStringConvertible {
  /// A message that names the problem and the fix.
  public var description: String {
    switch self {
    case let .rootNotFound(searchedFrom):
      "Bylaws cannot find a Swift package, Bazel workspace, Git repository "
        + "or Xcode project above '\(searchedFrom)'. Give the codebase "
        + "an explicit root, or run from inside the project."
    case let .notADirectory(path):
      "'\(path)' is not a directory. Point the codebase root at the "
        + "project directory."
    case let .languageModeUnavailable(path):
      "Bylaws cannot determine the Swift language mode from '\(path)'. "
        + "Set swiftLanguageMode on Codebase to match the target's build settings."
    case let .bazelGraph(path, reason):
      "Bylaws cannot read the Bazel graph at '\(path)'. \(reason) "
        + "Use Bazel 8 or later to export the full deps(...) query with --output=jsonproto "
        + "--transitions=lite --proto:include_configurations."
    case let .unreadable(failures):
      Self.description(of: failures)
    case let .didNotParse(diagnostics):
      diagnostics.map(\.description).joined(separator: "\n")
    case let .invalidRegularExpression(pattern):
      "Bylaws cannot compile '\(pattern)' as a regular expression. Fix the pattern."
    }
  }

  private static func description(of failures: [ReadFailure]) -> String {
    let details = failures.map { "'\($0.path)': \($0.reason)" }
    let paths = details.count == 1
      ? details[0]
      : "these paths: \(details.joined(separator: "; "))"
    return "Bylaws cannot read \(paths). A query needs every file under "
      + "the root."
  }
}

extension CodebaseError: LocalizedError {
  /// The same message as ``description``.
  public var errorDescription: String? { description }
}
