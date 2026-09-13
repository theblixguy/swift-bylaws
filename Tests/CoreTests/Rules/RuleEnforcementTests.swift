import Bylaws
import BylawsCore
import BylawsSemantics
import Testing

@Suite("Rule enforcement in tests")
struct RuleEnforcementTests {
  @available(macOS 15, *)
  @Test(
    "Advisory violation reports warning without trait",
    .compactMapIssues(advisoryIssues.record)
  )
  func advisoryViolation() async throws {
    let rule = Self.rule(for: "AdvisoryScreen")

    try await rule.report()

    let issues = Self.advisoryIssues.takeRecords()
    #expect(issues.count == 1)
    #expect(issues.first?.location == "App/Screens.swift:1:7")
  }

  @Test("Enforcement override applies to one report")
  func enforcedOverride() async throws {
    let rule = Self.rule(for: "OverrideScreen")

    await withKnownIssue("Enforced override reports violation") {
      try await rule.report(enforcement: .enforced)
    }
    try await rule.report()

    #expect(rule.enforcement == .advisory)
  }

  @Test("Advisory rule preserves unrelated test failures")
  func unrelatedFailure() async {
    let rule = Rule(
      "advisory-assertion", "Classes are final", enforcement: .advisory
    ) {
      Issue.record("Unrelated test failure")
      return Violations<Offender>(
        rule: "be final",
        offenders: [],
        checkedCount: 0
      )
    }

    await withKnownIssue("Rule body records unrelated failure") {
      try await rule.report()
    }
  }

  @Test(
    "Rule errors propagate for each enforcement",
    arguments: Enforcement.allCases
  )
  func executionError(_ enforcement: Enforcement) async {
    let rule = Rule(
      "throwing-rule",
      "Classes are final",
      enforcement: enforcement
    ) {
      throw MockError.failed
    }

    await #expect(throws: RuleError.self) {
      try await rule.report()
    }
  }

  @available(macOS 15, *)
  @Test(
    "Annotation preserves reported violation location",
    .annotatesViolations,
    .compactMapIssues(annotatedIssues.record),
    arguments: [Self.rule(for: "AnnotatedScreen")]
  )
  func annotatedLocation(_ rule: Rule) async throws {
    try await rule.report()

    let issues = Self.annotatedIssues.takeRecords()
    #expect(issues.count == 1)
    #expect(issues.first?.location == "App/Screens.swift:1:7")
  }

  private static func rule(for name: String) -> Rule {
    Rule(Rule.ID(name), "Classes are final", enforcement: .advisory) {
      try await Codebase(root: .sources([
        "App/Screens.swift": "class \(name) {}",
      ])).classes.violations(of: .isFinal)
    }
  }

  @available(macOS 15, *)
  private static let advisoryIssues = IssueRecorder(
    .containing("AdvisoryScreen"), severity: .warning
  )

  @available(macOS 15, *)
  private static let annotatedIssues = IssueRecorder(
    .containing("AnnotatedScreen"), severity: .warning
  )

  private enum MockError: Error {
    case failed
  }
}
