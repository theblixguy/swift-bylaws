#if os(macOS) || os(Linux)
  package import Testing

  package struct ProcessTestLimitTrait: TestTrait, SuiteTrait, TestScoping {
    package var isRecursive: Bool { true }

    package func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
      guard !test.isSuite else { return nil }
      if test.isParameterized { return testCase != nil ? self : nil }
      return testCase == nil ? self : nil
    }

    package func provideScope(
      for test: Test,
      testCase: Test.Case?,
      performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
      try await ProcessTestLimit.shared.withScope(performing: function)
    }
  }

  extension Trait where Self == ProcessTestLimitTrait {
    package static var processLimit: Self { Self() }
  }
#endif
