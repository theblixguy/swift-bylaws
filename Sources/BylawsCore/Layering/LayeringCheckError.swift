public import Foundation

/// A failure of a layering check over a codebase.
public enum LayeringCheckError: Error, Sendable, Hashable {
  /// The layering declaration is invalid.
  case invalidLayering(LayeringError)

  /// The codebase root or a source path cannot be read or parsed.
  case unreadableCodebase(CodebaseError)
}

extension LayeringCheckError: CustomStringConvertible {
  /// The message of the wrapped error.
  public var description: String {
    switch self {
    case let .invalidLayering(error): error.description
    case let .unreadableCodebase(error): error.description
    }
  }
}

extension LayeringCheckError: LocalizedError {
  /// The same message as ``description``.
  public var errorDescription: String? { description }
}
