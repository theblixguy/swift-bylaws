#if canImport(Testing)
  public import BylawsCore
  @_weakLinked public import Testing

  /// Shares a selection-cache budget across a test or suite.
  ///
  /// Tests and nested suites share the suite's cache unless they apply their own
  /// trait. Bylaws clears each cache when its test or suite finishes. Swift Testing
  /// evaluates test arguments before this scope starts.
  public struct SelectionCacheTrait: TestTrait, SuiteTrait, TestScoping,
    Sendable
  {
    /// The maximum estimated memory for retained selections, in bytes.
    public let budget: UInt

    /// Shares the cache throughout the suite or test, including all parameterised cases.
    public func scopeProvider(
      for test: Test,
      testCase: Test.Case?
    ) -> Self? {
      testCase == nil ? self : nil
    }

    /// Runs the suite or test with its shared selection cache.
    public func provideScope(
      for test: Test,
      testCase: Test.Case?,
      performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
      try await SelectionCache.withBudget(budget, operation: function)
    }
  }

  extension Trait where Self == SelectionCacheTrait {
    /// Sets the shared selection-cache budget for a test or suite.
    ///
    /// To turn off selection reuse within the scope, set `budget` to zero.
    /// The budget covers retained selections, excluding parsed files and rules
    /// currently running.
    public static func selectionCache(
      budget: UInt = SelectionCache.defaultBudget
    ) -> Self {
      Self(budget: budget)
    }
  }
#endif
