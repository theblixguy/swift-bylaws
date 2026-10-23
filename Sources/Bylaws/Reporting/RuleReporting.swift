#if canImport(Testing)
  public import BylawsCore
  @_weakLinked public import Testing

  extension Rule {
    /// Runs the rule and records each violation and warning as a test issue.
    ///
    /// Advisory violations remain visible without failing the test. Each
    /// violation uses its declaration's location. Warnings use `sourceLocation`.
    ///
    /// - Parameter enforcement: An override for this call, or `nil` to use the
    ///   rule's setting. Use `.enforced` to make advisory violations fail.
    /// - Parameter sourceLocation: The location for warnings. Defaults to the
    ///   call site.
    public func report(
      enforcement: Enforcement? = nil,
      sourceLocation: SourceLocation = #_sourceLocation
    ) async throws(RuleError) {
      let findings = try await findings()
      let enforcement = enforcement ?? self.enforcement
      FindingsReporting.report(
        findings,
        ruleID: id,
        name: name,
        enforcement: enforcement,
        hint: hint,
        location: location,
        origin: origin,
        sourceLocation: sourceLocation
      )
      TraitScope.completedRuleObserver?(id)
    }
  }

  extension Rule: CustomTestStringConvertible {
    /// The rule's display name, which names its test case.
    public var testDescription: String { name }
  }
#endif
