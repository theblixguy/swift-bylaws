public import Foundation

/// An error from reading a source file.
public enum ParseError: Error, Sendable, Hashable {
  /// The file cannot be opened, read or decoded as UTF-8.
  case unreadable(path: String, reason: String)

  /// The file has a syntax error, and the model is missing declarations
  /// from it.
  case didNotParse(diagnostics: [SourceParseDiagnostic])
}

extension ParseError: CustomStringConvertible {
  /// A message that names the problem and the fix.
  public var description: String {
    switch self {
    case let .unreadable(path, reason):
      "The file '\(path)' did not read: \(reason). Check that the file "
        + "exists and holds UTF-8 text."
    case let .didNotParse(diagnostics):
      diagnostics.map(\.description).joined(separator: "\n")
    }
  }
}

extension ParseError: LocalizedError {
  /// The same message as ``description``.
  public var errorDescription: String? { description }
}
