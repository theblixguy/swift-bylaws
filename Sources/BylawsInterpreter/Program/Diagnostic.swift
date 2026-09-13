public import BylawsSemantics
public import Foundation

/// A problem found while interpreting a rules file.
///
/// One load can report several diagnostics.
public struct Diagnostic: Error, Sendable, Hashable, Codable,
  CustomStringConvertible
{
  /// How a diagnostic counts against a load.
  public enum Severity: Sendable, Hashable, Codable {
    /// A construct failure that leaves the program incomplete.
    case error

    /// A problem reported for a construct that loaded.
    case warning

    /// Information that does not affect the load.
    case notice
  }

  /// How the diagnostic counts against the load.
  public let severity: Severity

  /// The position in the rules file the diagnostic points at.
  public let location: DeclarationLocation

  /// A one-sentence description of the problem.
  public let message: String

  /// The suggested fix, or `nil` when the message needs none.
  public let hint: String?

  /// Creates a diagnostic from its parts.
  public init(
    severity: Severity,
    location: DeclarationLocation,
    message: String,
    hint: String? = nil
  ) {
    self.severity = severity
    self.location = location
    self.message = message
    self.hint = hint
  }

  public var description: String {
    let label = switch severity {
    case .error: "error"
    case .warning: "warning"
    case .notice: "note"
    }
    let base = "\(location.filePath):\(location.line):\(location.column): "
      + "\(label): \(message)"
    guard let hint else { return base }
    return "\(base) (\(hint))"
  }
}

extension Diagnostic {
  static func error(
    _ message: String,
    at location: DeclarationLocation,
    hint: String? = nil
  ) -> Self {
    Self(severity: .error, location: location, message: message, hint: hint)
  }
}

extension Diagnostic: LocalizedError {
  /// The same message as ``description``.
  public var errorDescription: String? { description }
}
