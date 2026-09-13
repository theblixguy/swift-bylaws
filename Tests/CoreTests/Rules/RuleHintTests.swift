import Bylaws
import BylawsCore
import BylawsSemantics
import Testing

@Suite("Rule hints in Swift Testing issues")
struct RuleHintTests {
  @available(macOS 15, *)
  @Test(
    "Enforced violation includes rule hint",
    .compactMapIssues(violatingRuleIssues.record)
  )
  func violationHint() async throws {
    try await Self.rule(violating: true).report()

    #expect(
      Self.violatingRuleIssues.takeRecords().map(\.message)
        == [
          "class HomeScreen violates 'Screen classes say final' "
            + "(a screen belongs in Sources/App)",
        ]
    )
  }

  @available(macOS 15, *)
  @Test(
    "Passing rule reports no hint",
    .compactMapIssues(passingRuleIssues.record)
  )
  func passingRule() async throws {
    try await Self.rule(violating: false).report()

    #expect(Self.passingRuleIssues.takeRecords().isEmpty)
  }

  @available(macOS 15, *)
  private static let violatingRuleIssues = IssueRecorder(
    .containing(expectedHint)
  )

  @available(macOS 15, *)
  private static let passingRuleIssues = IssueRecorder(
    .equalTo(expectedHint),
    severity: .warning
  )

  private static let location = DeclarationLocation(
    filePath: "/project/Bylaws.swift", line: 3, column: 1, utf8Offset: 0
  )

  private static let expectedHint = "a screen belongs in Sources/App"

  private static func rule(violating: Bool) -> Rule {
    let offender = Offender(
      description: "class HomeScreen",
      name: "HomeScreen",
      location: location
    )
    return Rule(
      Rule.ID("final-screens"),
      "Screen classes say final",
      enforcement: .enforced,
      hint: expectedHint,
      location: location
    ) {
      Rule.Findings(
        violations: Violations(
          rule: "say final",
          offenders: violating ? [offender] : [],
          checkedCount: 1
        )
      )
    }
  }
}
