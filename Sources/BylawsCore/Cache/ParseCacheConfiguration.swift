public import Foundation

/// The disk cache settings for a codebase.
public struct ParseCacheConfiguration: Sendable, Hashable {
  /// The default cleanup target in bytes.
  public static let defaultBudget = 1_000_000_000

  /// The parent directory for the cache's `Bylaws` directory.
  ///
  /// A `nil` value uses `BYLAWS_CACHE_PATH` or the user's caches directory.
  public let directory: URL?

  /// The soft cleanup target in bytes. Zero disables the disk cache.
  ///
  /// The cache can exceed this target between cleanups. This setting applies
  /// to disk entries, which are separate from selections held in memory.
  public let budget: Int

  /// Creates disk cache settings that override environment defaults.
  ///
  /// `budget` must be zero or greater. An explicit configuration also enables
  /// caching for a codebase under a temporary directory.
  public init(directory: URL? = nil, budget: Int = Self.defaultBudget) {
    precondition(budget >= 0, "The cache budget must be zero or greater.")
    self.directory = directory
    self.budget = budget
  }
}
