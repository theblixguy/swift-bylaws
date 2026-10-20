package import BylawsSemantics

package struct SwiftTestingRuleReport: Sendable {
  package let version: Int
  package let sessionID: String
  package let testID: String
  package let ruleID: Rule.ID
  package let name: String
  package let enforcement: Enforcement
  package let hint: String?
  package let location: DeclarationLocation
  package let checks: [Violations<Offender>]
  package let warnings: [Rule.Warning]
  package let baselineAccepted: [Bool]
  package let origin: Rule.Origin?

  package var findings: Rule.Findings {
    Rule.Findings(checks: checks, warnings: warnings)
  }

  package init(
    sessionID: String,
    testID: String,
    ruleID: Rule.ID,
    name: String,
    enforcement: Enforcement,
    hint: String?,
    location: DeclarationLocation,
    findings: Rule.Findings,
    baselineAccepted: [Bool],
    origin: Rule.Origin?
  ) {
    version = SwiftTestingRuleSession.protocolVersion
    self.sessionID = sessionID
    self.testID = testID
    self.ruleID = ruleID
    self.name = name
    self.enforcement = enforcement
    self.hint = hint
    self.location = location
    checks = findings.checks
    warnings = findings.warnings
    self.baselineAccepted = baselineAccepted
    self.origin = origin
  }

  package func validate(in session: SwiftTestingRuleSession) throws {
    guard sessionID == session.id else {
      throw SwiftTestingRuleSessionError.mismatchedReport
    }
    try validateContents()
  }

  func validateContents() throws {
    guard version == SwiftTestingRuleSession.protocolVersion else {
      throw SwiftTestingRuleSessionError.unsupportedVersion(version)
    }
    guard !sessionID.isEmpty, !testID.isEmpty, !ruleID.rawValue.isEmpty else {
      throw SwiftTestingRuleSessionError.malformedReport(
        "The session, test and rule IDs must contain text"
      )
    }
    let baselineCountError = SwiftTestingRuleSessionError.malformedReport(
      "The baseline acceptance count must equal the offender count"
    )
    var checkedCount = 0
    var offenderCount = 0
    for check in checks {
      guard check.checkedCount >= 0 else {
        throw SwiftTestingRuleSessionError.malformedReport(
          "A check count must be zero or greater"
        )
      }
      let total = checkedCount.addingReportingOverflow(check.checkedCount)
      guard !total.overflow else {
        throw SwiftTestingRuleSessionError.malformedReport(
          "The check count total exceeds the supported integer range"
        )
      }
      checkedCount = total.partialValue
      guard check.offenders.count <= baselineAccepted.count - offenderCount
      else {
        throw baselineCountError
      }
      offenderCount += check.offenders.count
    }
    guard baselineAccepted.count == offenderCount else {
      throw baselineCountError
    }
  }
}
