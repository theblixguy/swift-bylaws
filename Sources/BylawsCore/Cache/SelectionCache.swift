/// A scope for sharing selections between compiled rules.
///
/// Codebases and child tasks within the scope share one budget for the estimated
/// memory used by cached selections, including source and filtered arrays, query
/// keys and cache entries. Memory used for parsed files and running rules is
/// outside this budget.
public enum SelectionCache {
  /// The default retained-selection budget, in bytes.
  public static let defaultBudget: UInt = 64 * 1024 * 1024

  @TaskLocal package static var current: SelectionCacheStore?

  /// Runs `operation` with a shared selection cache limited to `maximumBytes`.
  ///
  /// To turn off selection reuse, set the budget to zero.
  ///
  /// When the cache fills, Bylaws removes the least recently used entries first.
  /// Rules can use results that are too large to cache, but Bylaws may need to
  /// calculate them again for another rule.
  ///
  /// Bylaws clears the cache after `operation` finishes. Native Swift filter chains
  /// and custom closures run as usual.
  @concurrent
  public static func withBudget<Value: Sendable, Failure: Error>(
    _ maximumBytes: UInt = defaultBudget,
    operation: @Sendable () async throws(Failure) -> Value
  ) async throws(Failure) -> Value {
    let cache = maximumBytes > 0
      ? SelectionCacheStore(maximumBytes: maximumBytes) : nil
    let result = await $current.withValue(cache) {
      await Result(catching: operation)
    }
    await cache?.finish()
    return try result.get()
  }
}
