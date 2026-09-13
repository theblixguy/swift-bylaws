public import BylawsCore
public import Foundation

/// A failure to load the rules a project's `Bylaws.swift` files declare.
///
/// Later versions may add cases.
@nonexhaustive
public enum RuleDiscoveryError: Error, Sendable, Hashable {
  /// No project root can be resolved above the search path.
  case unresolvedRoot(CodebaseError)

  /// The rules load produced error diagnostics.
  case invalidRules(BylawsFileError)
}

extension RuleDiscoveryError: CustomStringConvertible {
  /// The message of the wrapped error.
  public var description: String {
    switch self {
    case let .unresolvedRoot(error): error.description
    case let .invalidRules(error): error.description
    }
  }
}

extension RuleDiscoveryError: LocalizedError {
  /// The same message as ``description``.
  public var errorDescription: String? { description }
}
