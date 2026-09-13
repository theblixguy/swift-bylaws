public import BylawsCore
public import BylawsIndexStore
public import Foundation

/// A failure to read a codebase's compiler index.
///
/// Later versions may add cases.
@nonexhaustive
public enum ProjectIndexError: Error, Sendable, Hashable {
  /// The codebase root cannot be resolved.
  case unreadableCodebase(CodebaseError)

  /// The index store is unavailable, unreadable, or lacks a requested
  /// module, output identity or build configuration.
  case indexUnavailable(IndexStoreError)
}

extension ProjectIndexError: CustomStringConvertible {
  /// The message of the wrapped error.
  public var description: String {
    switch self {
    case let .unreadableCodebase(error): error.description
    case let .indexUnavailable(error): error.description
    }
  }
}

extension ProjectIndexError: LocalizedError {
  /// The same message as ``description``.
  public var errorDescription: String? { description }
}
