public import BylawsCore
public import BylawsIndexStore
public import Foundation

/// A dependency check that cannot be configured or run.
@nonexhaustive
public enum DependencyCheckError: Error, Sendable, Hashable {
  /// The selected files cannot form the supplied dependency groups.
  case groups(DependencyGroupError)
  /// A path pattern is empty, absolute or contains unsupported components.
  case unsupportedPattern(String)
  /// A file belongs to several matching folder groups.
  case overlappingFolders(file: String, folders: [String])
  /// The codebase cannot be read or parsed.
  case unreadableCodebase(CodebaseError)
  /// The compiler index cannot be read for the selected build.
  case indexUnavailable(IndexStoreError)
}

extension DependencyCheckError: CustomStringConvertible, LocalizedError {
  /// The failure and the action to correct it.
  public var description: String {
    switch self {
    case let .groups(error): error.description
    case let .unsupportedPattern(pattern):
      "cannot use path pattern '\(pattern)'. Use a non-empty relative glob without '.' or '..' components."
    case let .overlappingFolders(file, folders):
      "'\(file)' belongs to several matching folders: \(folders.joined(separator: ", ")). Use a pattern that selects non-overlapping folders."
    case let .unreadableCodebase(error): error.description
    case let .indexUnavailable(error): error.description
    }
  }

  /// The same message as ``description``.
  public var errorDescription: String? { description }
}
