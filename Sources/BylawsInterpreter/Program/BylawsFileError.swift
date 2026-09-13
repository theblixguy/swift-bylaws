public import Foundation

/// An error containing diagnostics from Bylaws files that failed to load.
public struct BylawsFileError: Error, CustomStringConvertible, Sendable,
  Hashable
{
  /// Diagnostics produced while loading.
  public let diagnostics: [Diagnostic]

  /// Creates an error with diagnostics produced while loading.
  public init(diagnostics: [Diagnostic]) {
    self.diagnostics = diagnostics
  }

  public var description: String {
    let listing = diagnostics.map { "  \($0)" }.joined(separator: "\n")
    return "the Bylaws files did not load:\n\(listing)"
  }
}

extension BylawsFileError: LocalizedError {
  /// The same message as ``description``.
  public var errorDescription: String? { description }
}
