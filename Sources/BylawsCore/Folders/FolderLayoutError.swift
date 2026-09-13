public import Foundation

/// A folder layout that cannot be checked.
public enum FolderLayoutError: Error, Sendable, Hashable {
  /// The pattern cannot name folders relative to the codebase root.
  case unsupportedPattern(String)

  /// A required folder name is empty or contains path or glob syntax.
  case unsupportedFolderName(String)

  /// The codebase root or a directory cannot be read.
  case unreadableCodebase(CodebaseError)
}

extension FolderLayoutError: CustomStringConvertible, LocalizedError {
  /// The failed constraint or read operation.
  public var description: String {
    switch self {
    case let .unsupportedPattern(pattern):
      "Folder pattern '\(pattern)' must be relative to the codebase root. Use '/' between folders and omit null characters, '.' and '..' components."
    case let .unsupportedFolderName(name):
      "Folder name '\(name)' must be one non-empty path component. Use a child name without separators, glob characters or null characters."
    case let .unreadableCodebase(error): error.description
    }
  }

  /// The same message as ``description``.
  public var errorDescription: String? { description }
}
