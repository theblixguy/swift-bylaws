#if canImport(Testing)
  import BylawsSemantics
  @_weakLinked public import Testing

  /// Reports each failure at the checked declaration instead of the test.
  ///
  /// Apply it to a parameterised rule whose argument is one declaration.
  /// Every issue the rule records then appears at that declaration's file
  /// and line:
  ///
  /// ```swift
  /// @Test("ViewModels are final", .annotatesViolations,
  ///       arguments: try await Codebase.app.classes.suffixed("ViewModel"))
  /// func isFinal(_ viewModel: Class) {
  ///   #expect(viewModel.isFinal)
  /// }
  /// ```
  ///
  /// An issue stays at its `#expect` when the trait cannot identify one
  /// checked declaration. You can also pass `sourceLocation:` to `#expect`.
  ///
  /// Use the trait only on tests. Suites have no case argument.
  public struct AnnotatesViolationsTrait: TestTrait, TestScoping, Sendable {
    package static var currentDeclarationLocation: SourceLocation? {
      TraitScope.declaration?.testingLocation
    }

    public func provideScope(
      for test: Test,
      testCase: Test.Case?,
      performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
      guard let testCase, let declaration = Self.declaration(in: testCase)
      else {
        try await function()
        return
      }
      let location = declaration.testingLocation
      let relocating = IssueHandlingTrait.compactMapIssues { issue in
        var issue = issue
        issue.sourceLocation = TraitScope.reportedViolation?
          .offender.testingLocation ?? location
        return issue
      }
      try await TraitScope.$declaration.withValue(declaration) {
        try await relocating.provideScope(for: test, testCase: testCase) {
          try await function()
        }
      }
    }

    package static func declaration(in testCase: Test.Case) -> (any Located)? {
      let declarations = arguments(of: testCase)
        .compactMap { $0 as? any Located }
      guard Set(declarations.map(\.location)).count == 1 else { return nil }
      return declarations.first
    }

    // Test.Case.arguments is not public. Annotation reads Swift Testing's
    // storage layout and stops if that layout changes.
    private static func arguments(of testCase: Test.Case) -> [Any] {
      func child(_ value: Any, named name: String) -> Any? {
        Mirror(reflecting: value).children.first { $0.label == name }?.value
      }
      guard let kind = child(testCase, named: "_kind"),
            let parameterised = child(kind, named: "parameterized"),
            let list = child(parameterised, named: "arguments")
      else { return [] }
      return Mirror(reflecting: list).children.compactMap {
        child($0.value, named: "value")
      }
    }
  }

  extension Trait where Self == AnnotatesViolationsTrait {
    /// Reports each failure at the checked declaration instead of the test.
    public static var annotatesViolations: Self {
      Self()
    }
  }
#endif
