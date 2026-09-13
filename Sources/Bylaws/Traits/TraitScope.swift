#if canImport(Testing)
  import BylawsCore
  import BylawsSemantics

  enum TraitScope {
    @TaskLocal static var completedRuleObserver: (@Sendable (Rule.ID) -> Void)?
    @TaskLocal static var declaration: (any Located)?
    @TaskLocal static var reportedViolation: ReportedViolation?

    struct ReportedViolation: Sendable {
      let rule: Rule.ID
      let offender: Offender
    }
  }
#endif
