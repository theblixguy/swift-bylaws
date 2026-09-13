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
      for offender in findings.violations.offenders {
        let context = TraitScope.ReportedViolation(
          rule: id,
          offender: offender
        )
        TraitScope.$reportedViolation.withValue(context) {
          let comment = Comment(
            rawValue: "\(offender.description) violates '\(offender.requirement ?? name)'"
              + (hint.map { " (\($0))" } ?? "")
          )
          if enforcement == .advisory {
            Issue.recordWarning(
              comment,
              sourceLocation: offender.testingLocation
            )
          } else {
            Issue.record(comment, sourceLocation: offender.testingLocation)
          }
        }
      }
      for warning in findings.warnings {
        Issue.recordWarning(
          Comment(rawValue: warning.message),
          sourceLocation: sourceLocation
        )
      }
      TraitScope.completedRuleObserver?(id)
    }
  }

  extension Rule: CustomTestStringConvertible {
    /// The rule's display name, which names its test case.
    public var testDescription: String { name }
  }
#endif
