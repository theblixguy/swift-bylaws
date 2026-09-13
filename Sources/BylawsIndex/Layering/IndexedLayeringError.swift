public import BylawsCore
public import BylawsIndexStore
public import Foundation

/// A failure of an index-backed layering check over a codebase.
///
/// Later versions may add cases.
@nonexhaustive
public enum IndexedLayeringError: Error, Sendable, Hashable {
  /// The layering declaration is invalid.
  case invalidLayering(LayeringError)

  /// The codebase root or a source path cannot be read or parsed.
  case unreadableCodebase(CodebaseError)

  /// The index store is unavailable, unreadable, or lacks a requested
  /// module, output identity or build configuration.
  case indexUnavailable(IndexStoreError)
}

extension IndexedLayeringError: CustomStringConvertible {
  /// The message of the wrapped error.
  public var description: String {
    switch self {
    case let .invalidLayering(error): error.description
    case let .unreadableCodebase(error): error.description
    case let .indexUnavailable(error): error.description
    }
  }
}

extension IndexedLayeringError {
  package init(_ error: ProjectIndexError) {
    switch error {
    case let .unreadableCodebase(error): self = .unreadableCodebase(error)
    case let .indexUnavailable(error): self = .indexUnavailable(error)
    }
  }
}

extension IndexedLayeringError: LocalizedError {
  /// The same message as ``description``.
  public var errorDescription: String? { description }
}
