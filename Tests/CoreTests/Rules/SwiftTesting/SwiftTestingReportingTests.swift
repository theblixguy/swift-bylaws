import Bylaws
import BylawsCore
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Synchronization
import Testing

@Suite("Swift Testing rule collection")
struct SwiftTestingReportingTests {
  #if compiler(>=6.3)
    @available(macOS 15, *)
    @Test(
      "Collection preserves unrelated failure status",
      .compactMapIssues(recordUnrelated)
    )
    func unrelatedFailure() throws {
      let project = try TemporaryProject(files: [:])
      let session = session(in: project)
      let violations = Violations(
        rule: "be final", offenders: [offender(in: project)], checkedCount: 1
      )

      SwiftTestingRuleSession.$testingSession.withValue(session) {
        violations.report(ruleID: "final-classes")
        Issue.record("Unrelated Swift Testing reporting failure")
      }

      let failures = Self.unrelatedFailures.withLock { values in
        let result = values
        values.removeAll()
        return result
      }
      #expect(failures == [true])
    }

    @available(macOS 15, *)
    private static let unrelatedFailures = Mutex<[Bool]>([])

    @available(macOS 15, *)
    private static func recordUnrelated(_ issue: Issue) -> Issue? {
      guard issue.comments.contains(where: {
        $0.rawValue == "Unrelated Swift Testing reporting failure"
      }) else { return issue }
      unrelatedFailures.withLock { $0.append(issue.isFailure) }
      return nil
    }
  #endif

  @Test("Collection retains empty check outcome")
  func emptyOutcome() throws {
    let project = try TemporaryProject(files: [:])
    let session = session(in: project)
    let violations = Violations<Offender>(
      rule: "be final", offenders: [], checkedCount: 3
    )

    SwiftTestingRuleSession.$testingSession.withValue(session) {
      violations.report(ruleID: "final-classes")
    }

    let reports = try reports(in: project)
    #expect(reports.count == 1)
    let report = try #require(reports.first)
    #expect(report.ruleID == "final-classes")
    #expect(report.findings.violations.checkedCount == 3)
    #expect(report.findings.violations.isEmpty)
    #expect(report.baselineAccepted.isEmpty)
    #expect(!report.testID.isEmpty)
  }

  @Test("Default rule identity includes the owning test")
  func defaultRuleIdentity() throws {
    let project = try TemporaryProject(files: [:])
    let session = session(in: project)
    let test = try #require(Test.current)
    SwiftTestingRuleSession.$testingSession.withValue(session) {
      Violations<Offender>(rule: "be final", offenders: [], checkedCount: 0)
        .report()
    }

    let report = try #require(reports(in: project).first)
    #expect(report.ruleID == Rule.ID(String(describing: test.id)))
  }

  @Test("Rule collection preserves metadata and expected offender")
  func ruleOutcome() async throws {
    let project = try TemporaryProject(files: [:])
    let session = session(in: project)
    let offender = offender(in: project)
    var rule = Rule(
      "final-classes", "Classes are final", hint: "Add final."
    ) {
      Violations(rule: "be final", offenders: [offender], checkedCount: 1)
    }
    rule.origin = .init(filePath: "Bylaws.swift", ruleID: "final-classes")

    try await SwiftTestingRuleSession.$testingSession.withValue(session) {
      try await rule.report()
    }

    let report = try #require(reports(in: project).first)
    #expect(report.name == "Classes are final")
    #expect(report.hint == "Add final.")
    #expect(report.origin == rule.origin)
    #expect(report.findings.violations.offenders == [offender])
    #expect(report.baselineAccepted == [false])
  }

  @Test("Collection marks baseline accepted offenders")
  func baselineAcceptance() async throws {
    let project = try TemporaryProject(files: ["Package.swift": ""])
    let session = session(in: project)
    let offender = offender(in: project)
    let baseline = Baseline("app", entries: [
      .init(rule: "final-classes", declaration: "Screen", file: "Screen.swift"),
    ], file: project.fileURL(for: "Bylaws.baseline.swift").path)
    let trait = BaselineTrait.baseline(baseline)
    let test = try #require(Test.current)
    let rule = Rule("final-classes", "Classes are final") {
      Violations(rule: "be final", offenders: [offender], checkedCount: 1)
    }

    try await SwiftTestingRuleSession.$testingSession.withValue(session) {
      try await trait.provideScope(for: test, testCase: nil) {
        try await rule.report()
      }
    }

    let report = try #require(reports(in: project).first)
    #expect(report.baselineAccepted == [true])
  }

  @Test("Parallel reporting preserves every outcome")
  func parallelOutcomes() async throws {
    let project = try TemporaryProject(files: [:])
    let session = session(in: project)

    await SwiftTestingRuleSession.$testingSession.withValue(session) {
      await withTaskGroup(of: Void.self) { group in
        for index in 0..<20 {
          group.addTask {
            Violations<Offender>(
              rule: "be final", offenders: [], checkedCount: index
            ).report(ruleID: Rule.ID("rule-\(index)"))
          }
        }
      }
    }

    let reports = try reports(in: project)
    #expect(reports.count == 20)
    #expect(Set(reports.map(\.ruleID)).count == 20)
  }

  @Test("Collection rejects baseline recording before test body")
  func baselineRecording() async throws {
    let project =
      try TemporaryProject(files: ["Bylaws.baseline.swift": "unchanged"])
    let session = session(in: project)
    let baseline = Baseline(
      "app", entries: [],
      file: project.fileURL(for: "Bylaws.baseline.swift").path
    )
    let trait = BaselineTrait.baseline(baseline, mode: .record)
    let test = try #require(Test.current)

    await SwiftTestingRuleSession.$testingSession.withValue(session) {
      await #expect(throws: SwiftTestingRuleSessionError.baselineRecording) {
        try await trait.provideScope(for: test, testCase: nil) {
          Issue.record("The test body must remain uncalled")
        }
      }
    }

    #expect(try String(
      contentsOf: project.fileURL(for: "Bylaws.baseline.swift"),
      encoding: .utf8
    ) == "unchanged")
    #expect(try reports(in: project).isEmpty)
  }

  @Test("Collection preserves captured fix without changing source")
  func sourceFixOutcome() async throws {
    let source = "class Screen {}"
    let project = try TemporaryProject(files: ["Screen.swift": source])
    let session = session(in: project)
    let codebase = Codebase(
      root: .directory(project.rootURL.path), swiftLanguageMode: .v6
    )
    let violations = try await codebase.classes.violations(of: .isFinal)
      .withFix("Add final") { context in
        try context.source.slice(0..<0).replacement(with: "final ")
      }

    SwiftTestingRuleSession.$testingSession.withValue(session) {
      violations.report(ruleID: "final-classes")
    }

    let report = try #require(reports(in: project).first)
    let fix = try #require(report.findings.violations.fixes.first ?? nil)
    #expect(fix.title == "Add final")
    #expect(fix.edits.count == 1)
    #expect(fix.edits.first?.replacement == "final ")
    #expect(fix.edits.first?.source.file.text == source)
    #expect(try String(
      contentsOf: project.fileURL(for: "Screen.swift"),
      encoding: .utf8
    ) == source)
  }

  @Test("Report validation rejects another session")
  func reportSessionIdentity() throws {
    let project = try TemporaryProject(files: [:])
    let session = session(in: project)
    let report = SwiftTestingRuleReport(
      sessionID: "other-run", testID: "test", ruleID: "rule", name: "Rule",
      enforcement: .enforced, hint: nil,
      location: .init(filePath: "Rules.swift", line: 1, column: 1),
      findings: Rule.Findings(violations: Violations(
        rule: "be final", offenders: [], checkedCount: 0
      )), baselineAccepted: [], origin: nil
    )

    #expect(throws: SwiftTestingRuleSessionError.mismatchedReport) {
      try session.write(report)
    }
  }

  private func session(in project: TemporaryProject)
    -> SwiftTestingRuleSession
  {
    SwiftTestingRuleSession(
      id: UUID().uuidString,
      directory: project.rootURL.path,
      rootPath: project.rootURL.path
    )
  }

  private func offender(in project: TemporaryProject) -> Offender {
    Offender(
      description: "class Screen", name: "Screen",
      location: DeclarationLocation(
        filePath: project.fileURL(for: "Screen.swift").path,
        line: 1, column: 1
      )
    )
  }

  private func reports(in project: TemporaryProject) throws
    -> [SwiftTestingRuleReport]
  {
    try FileManager.default.contentsOfDirectory(
      at: project.rootURL, includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix("report-") }.map {
      try SwiftTestingRuleSession.readReport(at: $0)
    }
  }
}
