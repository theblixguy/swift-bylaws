/// The folders to skip when searching for rules and baselines.
///
/// Add one declaration to the root `Bylaws.swift` file:
///
/// ```swift
/// RuleDiscovery(excluding: ["Vendor", "**/Generated"])
/// ```
///
/// Patterns match folder paths relative to the project root and add to the
/// built-in exclusions. Each rule's ``Codebase`` selects the source files to check.
public struct RuleDiscovery: Sendable {
  /// The additional folder patterns excluded from discovery.
  public let excludedFolders: [Glob]

  /// Creates discovery settings with the folder patterns to exclude.
  @discardableResult
  public init(excluding folders: [Glob]) {
    excludedFolders = folders
  }
}
