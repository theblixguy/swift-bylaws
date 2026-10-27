#if canImport(Testing)
  import BylawsCore
  import BylawsSemantics
  import Foundation
  @_weakLinked import Testing

  enum FindingsReporting {
    static func report(
      _ findings: Rule.Findings,
      ruleID: Rule.ID,
      name: String,
      enforcement: Enforcement,
      hint: String?,
      location: DeclarationLocation,
      origin: Rule.Origin?,
      sourceLocation: SourceLocation
    ) {
      let collecting: Bool
      do {
        if let session = try SwiftTestingRuleSession.active() {
          guard let test = Test.current else {
            Issue.record(
              "Swift Testing rule reporting must run inside a test. Call report() from an @Test function.",
              sourceLocation: sourceLocation
            )
            return
          }
          let report = SwiftTestingRuleReport(
            sessionID: session.id,
            testID: String(describing: test.id),
            ruleID: ruleID,
            name: name,
            enforcement: enforcement,
            hint: hint,
            location: location,
            findings: findings,
            baselineAccepted: findings.checks.flatMap(\.offenders).map {
              TraitScope.acceptsReportedViolation?(ruleID, $0) == true
            },
            origin: origin
          )
          try session.write(report)
          collecting = true
        } else {
          collecting = false
        }
      } catch {
        Issue.record(
          Comment(rawValue: error.reportableDescription),
          sourceLocation: sourceLocation
        )
        return
      }

      let recordViolations = {
        for offender in findings.violations.offenders {
          let context = TraitScope.ReportedViolation(
            rule: ruleID,
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
      }
      if collecting {
        withKnownIssue(isIntermittent: true, sourceLocation: sourceLocation) {
          recordViolations()
        }
      } else {
        recordViolations()
        attachFixes(in: findings, sourceLocation: sourceLocation)
      }
      for warning in findings.warnings {
        Issue.recordWarning(
          Comment(rawValue: warning.message), sourceLocation: sourceLocation
        )
      }
    }

    private static func attachFixes(
      in findings: Rule.Findings,
      sourceLocation: SourceLocation
    ) {
      let fixes = findings.checks.flatMap { check in
        check.proposedFixes?.compactMap(\.self) ?? []
      }
      guard !fixes.isEmpty else { return }
      do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        Attachment.record(
          Array(try encoder.encode(fixes)),
          named: "bylaws-fixes.json",
          sourceLocation: sourceLocation
        )
      } catch {
        Issue.record(
          Comment(
            rawValue: "Cannot attach the source fixes: \(error.reportableDescription). Run the test again."
          ),
          sourceLocation: sourceLocation
        )
      }
    }
  }
#endif
