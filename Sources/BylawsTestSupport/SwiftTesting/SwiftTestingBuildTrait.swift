#if os(macOS) || os(Linux)
  package import Testing

  package struct SwiftTestingBuildTrait: TestTrait, SuiteTrait, TestScoping {
    package var isRecursive: Bool { true }

    package func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
      guard !test.isSuite else { return nil }
      if testCase != nil { return self }
      // Function scopes wait for capacity before the case time limit starts.
      return test.isParameterized ? nil : self
    }

    package func provideScope(
      for test: Test,
      testCase: Test.Case?,
      performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
      guard testCase != nil else {
        try await ProcessTestLimit.shared.withScope(performing: function)
        return
      }
      try await ProcessTestLimit.shared.withScope {
        try await SwiftTestingConsumerPool.shared
          .withScope(performing: function)
      }
    }
  }

  extension Trait where Self == SwiftTestingBuildTrait {
    package static var reuseSwiftTestingBuild: Self { Self() }
  }
#endif
