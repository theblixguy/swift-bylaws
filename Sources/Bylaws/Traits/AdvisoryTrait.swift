#if canImport(Testing)
  @_weakLinked public import Testing

  /// A trait that keeps issues visible without failing the suite or test.
  ///
  /// Swift 6.3 and later report advisory issues as warnings. Version 6.2 has
  /// no warning severity and reports them as known issues.
  public struct AdvisoryTrait: TestTrait, SuiteTrait, TestScoping, Sendable {
    public func provideScope(
      for test: Test,
      testCase: Test.Case?,
      performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
      #if compiler(>=6.3)
        let advisory = IssueHandlingTrait.compactMapIssues { issue in
          var issue = issue
          issue.severity = .warning
          return issue
        }
        try await advisory.provideScope(for: test, testCase: testCase) {
          try await function()
        }
      #else
        await withKnownIssue(isIntermittent: true) {
          try await function()
        }
      #endif
    }
  }

  extension Trait where Self == AdvisoryTrait {
    /// Keeps every issue in the suite or test visible without failing the run.
    public static var advisory: Self { Self() }
  }
#endif
