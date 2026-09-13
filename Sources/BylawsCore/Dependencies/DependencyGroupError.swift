public import Foundation

/// A dependency group that cannot be formed from the selected source files.
public enum DependencyGroupError: Error, Sendable, Hashable {
  /// A glob is empty, absolute or contains unsupported path components.
  case unsupportedPattern(String)
  /// A group name is empty or contains only whitespace.
  case emptyName
  /// Two groups in one check have the same name.
  case duplicateName(String)
  /// A selected source file belongs to more than one group.
  case overlappingGroups(file: String, groups: [String])
  /// A folder path cannot be represented by a literal file glob.
  case unsupportedFolderPath(String)
  /// The source selection cannot be read or parsed.
  case unreadableCodebase(CodebaseError)
}

extension DependencyGroupError: CustomStringConvertible, LocalizedError {
  /// The failure and the action to correct it.
  public var description: String {
    switch self {
    case let .unsupportedPattern(pattern):
      "cannot use path pattern '\(pattern)'. Use a non-empty relative glob without empty, '.' or '..' components, backslashes or null characters."
    case .emptyName:
      "DependencyGroup must have a non-empty name. Give each group a distinct name."
    case let .duplicateName(name):
      "DependencyGroup name '\(name)' must be unique within a check. Combine its file patterns or use distinct names."
    case let .overlappingGroups(file, groups):
      "'\(file)' belongs to several dependency groups: \(groups.joined(separator: ", ")). Change the patterns so each file belongs to at most one group."
    case let .unsupportedFolderPath(path):
      "cannot create a file glob for folder '\(path)'. Use folder names without '*', '?' or backslashes."
    case let .unreadableCodebase(error): error.description
    }
  }

  /// The same message as ``description``.
  public var errorDescription: String? { description }
}

extension DependencyGroup {
  package static func validate(pattern: String) throws(DependencyGroupError) {
    let components = pattern.split(
      separator: "/",
      omittingEmptySubsequences: false
    )
    guard !components.contains(""), !components.contains("."),
          !components.contains(".."), !pattern.contains("\\"),
          !pattern.contains("\0")
    else { throw .unsupportedPattern(pattern) }
  }
}
