import Bylaws
import BylawsCore
import BylawsSemantics
import Testing

@Suite("Rule issues in Swift Testing")
struct RuleReportingTests {
  @available(macOS 15, *)
  @Test(
    "Violation records declaration location",
    .compactMapIssues(violationIssues.record)
  )
  func violationLocation() async throws {
    let offender = Offender(
      description: "class HomeViewModel",
      name: "HomeViewModel",
      location: DeclarationLocation(
        filePath: "/project/Sources/App/Screens.swift",
        line: 7,
        column: 5,
        utf8Offset: 100
      )
    )
    let rule = Rule("final-classes", "Classes are final") {
      Violations(
        rule: "be final",
        offenders: [offender],
        checkedCount: 1
      )
    }

    try await rule.report()

    let issues = Self.violationIssues.takeRecords()
    #expect(issues.count == 1)
    #expect(issues.first?.location == "App/Screens.swift:7:5")
  }

  @available(macOS 15, *)
  @Test(
    "Rule warning records issue with warning severity",
    .compactMapIssues(warningIssues.record)
  )
  func warningRecords() async throws {
    let location = DeclarationLocation(
      filePath: "/project/Bylaws.swift", line: 3, column: 1, utf8Offset: 0
    )
    let warning = Rule.Warning(
      message: Self.expectedWarningMessage,
      location: location
    )
    let rule = Rule(
      Rule.ID("layering"),
      "The declared layering holds",
      enforcement: .enforced,
      location: location
    ) {
      Rule.Findings(
        violations: Violations(rule: "hold", offenders: [], checkedCount: 1),
        warnings: [warning]
      )
    }

    try await rule.report()
    let issues = Self.warningIssues.takeRecords()
    #expect(issues.count == 1)
    #expect(issues.first?.message == warning.message)
  }

  @available(macOS 15, *)
  private static let violationIssues = IssueRecorder(
    .equalTo(expectedViolationMessage), severity: .error
  )

  @available(macOS 15, *)
  private static let warningIssues = IssueRecorder(
    .equalTo(expectedWarningMessage),
    severity: .warning
  )

  private static let expectedViolationMessage =
    "class HomeViewModel violates 'Classes are final'"

  private static let expectedWarningMessage =
    "layer 'Ghost' matched no files"
}
