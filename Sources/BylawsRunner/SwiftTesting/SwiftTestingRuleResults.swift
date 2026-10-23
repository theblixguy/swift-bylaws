import BylawsCore
import BylawsSemantics

package enum SwiftTestingRuleResults {
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
    var unmatched = reports
    for prior in previous {
      guard let index = unmatched
        .firstIndex(where: { sameDefinition(prior, $0) })
      else {
        throw CaptureError(
          "Swift Testing rule '\(prior.ruleID)' did not repeat a check during verification. Report each check when it passes and keep its test and metadata stable"
        )
      }
      unmatched.remove(at: index)
    }
    return reports
  }

  struct CollectedRule: Sendable {
    let rule: Rule
    let reportableViolations: Violations<Offender>

    fileprivate init(rule: Rule, reportableViolations: Violations<Offender>) {
      self.rule = rule
      self.reportableViolations = reportableViolations
    }
  }

  package struct Collection: Sendable {
    package static let empty = Self(rules: [], acceptedPortableOffenders: [:])

    let rules: [CollectedRule]
    let acceptedPortableOffenders: [Rule.Origin: Set<Offender>]

    fileprivate init(
      rules: [CollectedRule],
      acceptedPortableOffenders: [Rule.Origin: Set<Offender>]
    ) {
      self.rules = rules
      self.acceptedPortableOffenders = acceptedPortableOffenders
    }
  }

  static func collect(
    from reports: [SwiftTestingRuleReport], alongside portable: [Rule]
  ) throws -> Collection {
    let portableByID = Dictionary(grouping: portable, by: \.id)
    var acceptedPortable: [Rule.Origin: Set<Offender>] = [:]
    var grouped: [Rule.ID: [SwiftTestingRuleReport]] = [:]
    for report in reports {
      try validateAcceptance(in: report)
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
      .compactMap { id -> CollectedRule? in
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
        let rule = Rule(
          id, first.name, enforcement: first.enforcement,
          hint: first.hint, location: first.location
        ) { findings }
        let reportable = Rule.Findings(checks: group.flatMap(reportableChecks))
        return CollectedRule(
          rule: rule, reportableViolations: reportable.violations
        )
      }
    return Collection(
      rules: rules,
      acceptedPortableOffenders: acceptedPortable
    )
  }

  private static func validateAcceptance(
    in report: SwiftTestingRuleReport
  ) throws {
    var remaining = report.baselineAccepted.count
    for check in report.checks {
      guard check.offenders.count <= remaining else {
        throw SwiftTestingRuleSessionError.malformedReport(
          "The baseline acceptance count must equal the offender count"
        )
      }
      remaining -= check.offenders.count
    }
    guard remaining == 0 else {
      throw SwiftTestingRuleSessionError.malformedReport(
        "The baseline acceptance count must equal the offender count"
      )
    }
  }

  private static func reportableChecks(
    from report: SwiftTestingRuleReport
  ) -> [Violations<Offender>] {
    var remaining = report.baselineAccepted[...]
    return report.checks.map { check in
      var accepted = remaining.prefix(check.offenders.count).makeIterator()
      remaining = remaining.dropFirst(check.offenders.count)
      return check.filteringOffenders { _ in accepted.next() == false }
    }
  }

  private static func sameDefinition(
    _ first: SwiftTestingRuleReport, _ second: SwiftTestingRuleReport
  ) -> Bool {
    first.ruleID == second.ruleID && first.testID == second.testID
      && first.name == second.name && first.origin == second.origin
      && first.enforcement == second.enforcement && first.hint == second.hint
  }
}
