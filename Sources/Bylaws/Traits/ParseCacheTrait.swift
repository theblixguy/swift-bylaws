#if canImport(Testing)
  public import BylawsCore
  public import Foundation
  @_weakLinked public import Testing

  /// Sets disk-cache defaults for a suite or test.
  ///
  /// Omitted settings come from the enclosing scope or the cache defaults.
  /// An explicit configuration on a `Codebase` takes precedence.
  /// Swift Testing evaluates `arguments:` before entering this scope. Set
  /// `Codebase(parseCache:)` explicitly for queries that produce test arguments.
  public struct ParseCacheTrait: TestTrait, SuiteTrait, TestScoping, Sendable {
    let directory: URL?
    let budget: Int?
    let validation: ParseCacheConfiguration.Validation?

    /// Applies settings to the whole suite or test, including all parameterised cases.
    public func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
      testCase == nil ? self : nil
    }

    /// Runs the suite or test with its disk-cache settings.
    public func provideScope(
      for test: Test,
      testCase: Test.Case?,
      performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
      let configuration = applying(to: ParseCacheConfiguration.current)
      try await ParseCacheConfiguration.$current.withValue(configuration) {
        try await function()
      }
    }

    static func withConfiguration(
      for test: Test,
      performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
      let configuration = test.traits.compactMap { $0 as? Self }.reduce(
        ParseCacheConfiguration.current
      ) { configuration, trait in
        trait.applying(to: configuration)
      }
      try await ParseCacheConfiguration.$current.withValue(configuration) {
        try await function()
      }
    }

    private func applying(
      to inherited: ParseCacheConfiguration?
    ) -> ParseCacheConfiguration {
      let defaults = inherited ?? ParseCacheConfiguration()
      return ParseCacheConfiguration(
        directory: directory ?? defaults.directory,
        budget: budget ?? defaults.budget,
        validation: validation ?? defaults.validation
      )
    }
  }

  extension Trait where Self == ParseCacheTrait {
    /// Sets disk-cache defaults while keeping omitted settings from the enclosing scope.
    ///
    /// The directory is a `URL` beneath which Bylaws creates its cache folder.
    /// The budget is a soft disk-size target in bytes. Zero disables disk caching.
    /// At the outermost scope, omitted settings use the cache's default directory,
    /// 1 GB budget and metadata validation. A non-zero budget enables caching,
    /// including for temporary projects, and overrides `BYLAWS_DISABLE_PARSE_CACHE`.
    public static func parseCache(
      directory: URL? = nil,
      budget: Int? = nil,
      validation: ParseCacheConfiguration.Validation? = nil
    ) -> Self {
      if let budget {
        precondition(budget >= 0, "The cache budget must be zero or greater.")
      }
      return Self(directory: directory, budget: budget, validation: validation)
    }
  }
#endif
