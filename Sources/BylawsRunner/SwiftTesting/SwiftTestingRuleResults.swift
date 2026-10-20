import BylawsCore
import BylawsSemantics

enum SwiftTestingRuleResults {
  static func reports(
    from run: SwiftPMTestRun?,
    verifying previous: [SwiftTestingRuleReport]
  ) throws -> [SwiftTestingRuleReport] {
    let reports = run?.reports ?? []
    let reported = Set(reports.map(\.ruleID))
    if let missing = previous.first(where: { !reported.contains($0.ruleID) }) {
      throw CaptureError(
        "Swift Testing rule '\(missing.ruleID)' did not report during verification. Report the whole check from a test that still runs when it passes"
      )
    }
    if let changed = previous.first(where: { prior in
      !reports.contains { sameDefinition(prior, $0) }
    }) {
      throw CaptureError(
        "Swift Testing rule '\(changed.ruleID)' changed its definition during verification. Keep its test and metadata stable"
      )
    }
    return reports
  }

  struct Collection {
    let rules: [Rule]
    let acceptedOffenders: [Rule.ID: [Bool]]
    let acceptedPortableOffenders: [Rule.Origin: Set<Offender>]
  }

  static func collect(
    from reports: [SwiftTestingRuleReport], alongside portable: [Rule]
  ) throws -> Collection {
    let portableByID = Dictionary(grouping: portable, by: \.id)
    var acceptedPortable: [Rule.Origin: Set<Offender>] = [:]
    var grouped: [Rule.ID: [SwiftTestingRuleReport]] = [:]
    for report in reports {
      if let existing = portableByID[report.ruleID] {
        guard let origin = report.origin,
              existing.contains(where: { $0.origin == origin })
        else {
          throw CaptureError(
            "rule ID '\(report.ruleID)' names both a portable rule and a Swift Testing rule"
          )
        }
        for (offender, accepted) in zip(
          report.findings.violations.offenders, report.baselineAccepted
        ) where accepted {
          acceptedPortable[origin, default: []].insert(offender)
        }
        continue
      }
      if let previous = grouped[report.ruleID]?.first {
        guard sameDefinition(previous, report) else {
          throw CaptureError(
            "rule ID '\(report.ruleID)' names different Swift Testing rules"
          )
        }
      }
      grouped[report.ruleID, default: []].append(report)
    }
    let rules = try grouped.keys.sorted { $0.rawValue < $1.rawValue }
      .compactMap { id -> Rule? in
        guard let group = grouped[id],
              let first = group.first else { return nil }
        let checks = group.flatMap(\.checks)
        var checkedCount = 0
        for check in checks {
          let sum = checkedCount.addingReportingOverflow(check.checkedCount)
          guard !sum.overflow else {
            throw CaptureError(
              "Swift Testing rule '\(id)' must report a combined checked count within Int.max. Reduce the count reported by its test cases"
            )
          }
          checkedCount = sum.partialValue
        }
        let findings = Rule.Findings(
          checks: checks,
          warnings: group.flatMap(\.warnings)
        )
        return Rule(
          id, first.name, enforcement: first.enforcement,
          hint: first.hint, location: first.location
        ) { findings }
      }
    return Collection(
      rules: rules,
      acceptedOffenders: grouped.mapValues { $0.flatMap(\.baselineAccepted) },
      acceptedPortableOffenders: acceptedPortable
    )
  }

  private static func sameDefinition(
    _ first: SwiftTestingRuleReport, _ second: SwiftTestingRuleReport
  ) -> Bool {
    first.ruleID == second.ruleID && first.testID == second.testID
      && first.name == second.name && first.origin == second.origin
      && first.enforcement == second.enforcement && first.hint == second.hint
  }
}
