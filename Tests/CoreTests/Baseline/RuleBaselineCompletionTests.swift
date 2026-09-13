import Bylaws
import BylawsCore
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Completed rule baselines")
struct RuleBaselineCompletionTests {
  @Test("Advisory violation saved in baseline")
  func recordedAdvisoryEntry() async throws {
    let project = try TemporaryProject(files: [:])
    let file = project.fileURL(for: "Baseline.swift")
    let baseline = Baseline("advisoryRule", entries: [], file: file.path)
    let trait: BaselineTrait = .baseline(baseline, mode: .record)
    let test = try #require(Test.current)
    let rule = Rule(
      "advisory-rule", "Classes are final", enforcement: .advisory
    ) {
      try await Codebase(root: .sources([
        "App/Screen.swift": "class HomeScreen {}",
      ])).classes.violations(of: .isFinal)
    }

    try await withKnownIssue("Baseline recording fails test for review") {
      try await trait.provideScope(for: test, testCase: nil) {
        try await rule.report()
      }
    } matching: { issue in
      issue.comments.contains { $0.rawValue.hasPrefix("Recorded 1 violation") }
    }

    let contents = try String(contentsOf: file, encoding: .utf8)
    #expect(contents == BaselineFile.render(name: "advisoryRule", entries: [
      Baseline.Entry(
        rule: "advisory-rule", declaration: "HomeScreen",
        file: "App/Screen.swift"
      ),
    ]))
  }

  @Test("Advisory violation matches existing baseline")
  func advisoryEntry() async throws {
    let baseline = Baseline("advisoryRule", entries: [
      Baseline.Entry(
        rule: "advisory-rule", declaration: "HomeScreen",
        file: "App/Screen.swift"
      ),
    ])
    let trait: BaselineTrait = .baseline(baseline)
    let test = try #require(Test.current)
    let rule = Rule(
      "advisory-rule", "Classes are final", enforcement: .advisory
    ) {
      try await Codebase(root: .sources([
        "App/Screen.swift": "class HomeScreen {}",
      ])).classes.violations(of: .isFinal)
    }

    try await trait.provideScope(for: test, testCase: nil) {
      try await rule.report()
    }
  }

  #if compiler(>=6.3)
    @Test("Diagnostic warning excluded from baseline")
    func diagnosticWarning() async throws {
      let project = try TemporaryProject(files: [:])
      let file = project.fileURL(for: "Baseline.swift")
      let baseline = Baseline("warnings", entries: [], file: file.path)
      let trait: BaselineTrait = .baseline(baseline, mode: .record)
      let test = try #require(Test.current)
      let rule = Rule("empty-layer", "Layers follow permitted dependencies") {
        Rule.Findings(
          violations: Violations(
            rule: "be final",
            offenders: [],
            checkedCount: 0
          ),
          warnings: [Rule.Warning(
            message: "Layer 'Views' matched no files",
            location: .init(
              filePath: "/project/Bylaws.swift", line: 1, column: 1,
              utf8Offset: 0
            )
          )]
        )
      }

      try await withKnownIssue("Baseline recording fails test for review") {
        try await trait.provideScope(for: test, testCase: nil) {
          try await rule.report()
        }
      } matching: { issue in
        issue.comments
          .contains { $0.rawValue.hasPrefix("Recorded 0 violations") }
      }

      let contents = try String(contentsOf: file, encoding: .utf8)
      #expect(contents == BaselineFile.render(name: "warnings", entries: []))
    }
  #endif

  @available(macOS 15, *)
  @Test(
    "Completed rule reports stale baseline entry without trait",
    .compactMapIssues(staleIssues.record)
  )
  func staleEntry() async throws {
    let baseline = Baseline("completedRule", entries: [
      Baseline.Entry(
        rule: "fixed-rule", declaration: "HomeScreen", file: "App/Screen.swift"
      ),
      Baseline.Entry(
        rule: "skipped-rule", declaration: "SkippedScreen",
        file: "App/Screen.swift"
      ),
    ])
    let trait: BaselineTrait = .baseline(baseline)
    let test = try #require(Test.current)
    let rule = Rule("fixed-rule", "Classes are final") {
      Violations<Offender>(rule: "be final", offenders: [], checkedCount: 1)
    }

    try await trait.provideScope(for: test, testCase: nil) {
      try await rule.report()
    }

    let issues = Self.staleIssues.takeRecords()
    #expect(issues.count == 1)
    #expect(issues.first?.message.contains("HomeScreen") == true)
    #expect(issues.first?.message.contains("SkippedScreen") == false)
  }

  @available(macOS 15, *)
  @Test(
    "Failed rule leaves baseline entries unchecked",
    .compactMapIssues(failedRuleIssues.record)
  )
  func failedRule() async throws {
    let baseline = Baseline("failedRule", entries: [
      Baseline.Entry(
        rule: "failed-rule", declaration: "HomeScreen", file: "App/Screen.swift"
      ),
    ])
    let trait: BaselineTrait = .baseline(baseline)
    let test = try #require(Test.current)
    let rule = Rule("failed-rule", "Classes are final") {
      throw MockError.failed
    }

    try await trait.provideScope(for: test, testCase: nil) {
      await #expect(throws: RuleError.self) {
        try await rule.report()
      }
    }

    #expect(Self.failedRuleIssues.takeRecords().isEmpty)
  }

  @available(macOS 15, *)
  private static let staleIssues = IssueRecorder(
    .containing("The baseline 'completedRule' has 1 stale entry")
  )

  @available(macOS 15, *)
  private static let failedRuleIssues = IssueRecorder(
    .containing("The baseline 'failedRule'")
  )

  private enum MockError: Error {
    case failed
  }
}
