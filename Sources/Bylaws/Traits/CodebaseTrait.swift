#if canImport(Testing)
  public import BylawsCore
  @_weakLinked public import Testing

  /// Prepares a codebase before a suite runs.
  ///
  /// Root-resolution errors fail the suite once. Inside the suite,
  /// ``/BylawsCore/Codebase/current`` names the prepared codebase for each
  /// test, parameterised case and nested suite.
  public struct CodebaseTrait: SuiteTrait, TestScoping, Sendable {
    /// The codebase this suite lints.
    public let codebase: Codebase

    public func prepare(for test: Test) async throws {
      _ = try codebase.resolvedRootPath()
    }

    public func provideScope(
      for test: Test,
      testCase: Test.Case?,
      performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
      try await ParseCacheTrait.withConfiguration(for: test) {
        try await codebase.prepare()
        try await Codebase.$current.withValue(codebase) {
          try await function()
        }
      }
    }
  }

  extension Trait where Self == CodebaseTrait {
    /// Parses `codebase` and binds it as the suite's current codebase.
    public static func codebase(_ codebase: Codebase) -> Self {
      Self(codebase: codebase)
    }
  }
#endif
