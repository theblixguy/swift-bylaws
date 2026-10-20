import Bylaws
import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Synchronization
import Testing

@Suite("Swift Testing baseline reporting")
struct SwiftTestingBaselineReportingTests {
  @available(macOS 15, *)
  @Test("Nested baseline checks its stale entries during collection")
  func nestedStaleEntry() async throws {
    let project = try TemporaryProject(files: ["Package.swift": ""])
    let session = session(in: project)
    let outer = BaselineTrait.baseline(Baseline(
      "outer", entries: [], file: project.fileURL(for: "Outer.swift").path
    ))
    let inner = BaselineTrait.baseline(Baseline("inner", entries: [
      .init(rule: "classes", declaration: "Screen", file: "Screen.swift"),
      .init(
        rule: "classes",
        declaration: "RemovedScreen",
        file: "Screen.swift"
      ),
    ], file: project.fileURL(for: "Inner.swift").path))
    let issues = IssueRecorder(.containing("The baseline 'inner'"))
    let handling = IssueHandlingTrait.compactMapIssues(issues.record)
    let test = try #require(Test.current)
    let violations = violations(in: project)

    try await handling.provideScope(for: test, testCase: nil) {
      try await SwiftTestingRuleSession.$testingSession.withValue(session) {
        try await outer.provideScope(for: test, testCase: nil) {
          try await inner.provideScope(for: test, testCase: nil) {
            violations.report(ruleID: "classes")
          }
        }
      }
    }

    let recorded = issues.takeRecords()
    #expect(recorded.count == 1)
    #expect(recorded.first?.message.contains("1 stale entry") == true)
    #expect(recorded.first?.message.contains("RemovedScreen") == true)
    #expect(recorded.first?.message.contains("classes: Screen (") == false)
    let reports = try reports(in: project)
    #expect(reports.count == 1)
    #expect(reports.first?.baselineAccepted == [true])
  }

  @available(macOS 15, *)
  @Test(
    "Nested baselines retain acceptance from either scope",
    arguments: [false, true]
  )
  func nestedAcceptance(acceptedByInner: Bool) async throws {
    let project = try TemporaryProject(files: ["Package.swift": ""])
    let session = session(in: project)
    let entries = [Baseline.Entry(
      rule: "classes", declaration: "Screen", file: "Screen.swift"
    )]
    let outer = BaselineTrait.baseline(Baseline(
      "outer", entries: acceptedByInner ? [] : entries,
      file: project.fileURL(for: "Outer.swift").path
    ))
    let inner = BaselineTrait.baseline(Baseline(
      "inner", entries: acceptedByInner ? entries : [],
      file: project.fileURL(for: "Inner.swift").path
    ))
    let test = try #require(Test.current)
    let violations = violations(in: project)

    try await SwiftTestingRuleSession.$testingSession.withValue(session) {
      try await outer.provideScope(for: test, testCase: nil) {
        try await inner.provideScope(for: test, testCase: nil) {
          violations.report(ruleID: "classes")
        }
      }
    }

    let reports = try reports(in: project)
    #expect(reports.count == 1)
    #expect(reports.first?.baselineAccepted == [true])
  }

  @available(macOS 15, *)
  @Test("Nested scope forwards completed rule to outer baseline")
  func outerStaleEntry() async throws {
    let project = try TemporaryProject(files: ["Package.swift": ""])
    let session = session(in: project)
    let outer = BaselineTrait.baseline(Baseline("outer", entries: [
      .init(
        rule: "classes",
        declaration: "RemovedScreen",
        file: "Screen.swift"
      ),
    ], file: project.fileURL(for: "Outer.swift").path))
    let inner = BaselineTrait.baseline(Baseline(
      "inner", entries: [], file: project.fileURL(for: "Inner.swift").path
    ))
    let issues = IssueRecorder(.containing("The baseline 'outer'"))
    let handling = IssueHandlingTrait.compactMapIssues(issues.record)
    let test = try #require(Test.current)

    try await handling.provideScope(for: test, testCase: nil) {
      try await SwiftTestingRuleSession.$testingSession.withValue(session) {
        try await outer.provideScope(for: test, testCase: nil) {
          try await inner.provideScope(for: test, testCase: nil) {
            Violations<Offender>(
              rule: "be final",
              offenders: [],
              checkedCount: 1
            )
            .report(ruleID: "classes")
          }
        }
      }
    }

    let recorded = issues.takeRecords()
    #expect(recorded.count == 1)
    #expect(recorded.first?.message.contains("RemovedScreen") == true)
  }

  @available(macOS 15, *)
  @Test("Recursive trait copy checks stale entries once")
  func recursiveTrait() async throws {
    let project = try TemporaryProject(files: ["Package.swift": ""])
    let session = session(in: project)
    let trait = BaselineTrait.baseline(Baseline("recursive", entries: [
      .init(
        rule: "classes",
        declaration: "RemovedScreen",
        file: "Screen.swift"
      ),
    ], file: project.fileURL(for: "Baseline.swift").path))
    let inherited = trait
    let issues = IssueRecorder(.containing("The baseline 'recursive'"))
    let handling = IssueHandlingTrait.compactMapIssues(issues.record)
    let test = try #require(Test.current)

    try await handling.provideScope(for: test, testCase: nil) {
      try await SwiftTestingRuleSession.$testingSession.withValue(session) {
        try await trait.provideScope(for: test, testCase: nil) {
          try await inherited.provideScope(for: test, testCase: nil) {
            Violations<Offender>(
              rule: "be final",
              offenders: [],
              checkedCount: 1
            )
            .report(ruleID: "classes")
          }
        }
      }
    }

    #expect(issues.takeRecords().count == 1)
  }

  @available(macOS 15, *)
  @Test(
    "Inferred parameter rule leaves other baseline entries unchecked",
    arguments: ["Screen", "OtherScreen"]
  )
  func partialCase(name: String) async throws {
    let project = try TemporaryProject(files: ["Package.swift": ""])
    let session = session(in: project)
    let test = try #require(Test.current)
    let ruleID = Rule.ID(String(describing: test.id))
    let baseline = Baseline("partial", entries: [
      .init(rule: ruleID, declaration: "Screen", file: "Screen.swift"),
      .init(rule: ruleID, declaration: "OtherScreen", file: "Screen.swift"),
    ], file: project.fileURL(for: "Baseline.swift").path)
    let trait = BaselineTrait.baseline(baseline)
    let violations = violations(in: project, name: name)
    let issues = IssueRecorder(.containing("The baseline 'partial'"))
    let handling = IssueHandlingTrait.compactMapIssues(issues.record)

    try await handling.provideScope(for: test, testCase: nil) {
      try await SwiftTestingRuleSession.$testingSession.withValue(session) {
        try await trait.provideScope(for: test, testCase: nil) {
          violations.report()
        }
      }
    }

    #expect(issues.takeRecords().isEmpty)
  }

  @available(macOS 15, *)
  @Test(
    "Explicit parameter rule ID checks every baseline entry",
    arguments: ["Screen", "OtherScreen"]
  )
  func explicitCase(name: String) async throws {
    let project = try TemporaryProject(files: ["Package.swift": ""])
    let session = session(in: project)
    let test = try #require(Test.current)
    let baseline = Baseline("explicit", entries: [
      .init(rule: "classes", declaration: "Screen", file: "Screen.swift"),
      .init(rule: "classes", declaration: "OtherScreen", file: "Screen.swift"),
    ], file: project.fileURL(for: "Baseline.swift").path)
    let trait = BaselineTrait.baseline(baseline)
    let violations = violations(in: project, name: name)
    let issues = IssueRecorder(.containing("The baseline 'explicit'"))
    let handling = IssueHandlingTrait.compactMapIssues(issues.record)

    try await handling.provideScope(for: test, testCase: nil) {
      try await SwiftTestingRuleSession.$testingSession.withValue(session) {
        try await trait.provideScope(for: test, testCase: nil) {
          violations.report(ruleID: "classes")
        }
      }
    }

    let recorded = issues.takeRecords()
    let unmatched = name == "Screen" ? "OtherScreen" : "Screen"
    #expect(recorded.count == 1)
    #expect(recorded.first?.message.contains("classes: \(unmatched) (") == true)
    #expect(recorded.first?.message.contains("classes: \(name) (") == false)
  }

  @available(macOS 15, *)
  @Test(
    "Nested record mode preserves unrun parameter entries",
    arguments: ["Screen", "OtherScreen"]
  )
  func recordPartialCase(name: String) async throws {
    let project = try TemporaryProject(files: ["Package.swift": ""])
    let test = try #require(Test.current)
    let ruleID = Rule.ID(String(describing: test.id))
    let file = project.fileURL(for: "Baseline.swift")
    let entries = [
      Baseline.Entry(rule: ruleID, declaration: "Screen", file: "Screen.swift"),
      Baseline.Entry(
        rule: ruleID,
        declaration: "OtherScreen",
        file: "Screen.swift"
      ),
    ]
    let baseline = Baseline("partialRecord", entries: entries, file: file.path)
    let outer = BaselineTrait.baseline(baseline)
    let inner = BaselineTrait.baseline(baseline, mode: .record)
    let violations = violations(in: project, name: name)
    let issues = IssueRecorder(.containing("Recorded "))
    let handling = IssueHandlingTrait.compactMapIssues(issues.record)

    try await handling.provideScope(for: test, testCase: nil) {
      try await outer.provideScope(for: test, testCase: nil) {
        try await inner.provideScope(for: test, testCase: nil) {
          violations.report()
        }
      }
    }

    let recorded = issues.takeRecords()
    #expect(recorded.count == 1)
    #expect(recorded.first?.message.hasPrefix("Recorded 2 violations") == true)
    #expect(Set(try Baseline.entries(fromFile: file.path)) == Set(entries))
  }

  #if compiler(>=6.3)
    @available(macOS 15, *)
    @Test("Nested baselines preserve unrelated failure status")
    func unrelatedFailure() async throws {
      let project = try TemporaryProject(files: ["Package.swift": ""])
      let session = session(in: project)
      let outer = BaselineTrait.baseline(Baseline("outer", entries: []))
      let inner = BaselineTrait.baseline(Baseline("inner", entries: []))
      let test = try #require(Test.current)
      let failures = Mutex<[Bool]>([])
      let handling = IssueHandlingTrait.compactMapIssues { issue in
        guard issue.comments.contains(where: {
          $0.rawValue == "Unrelated nested baseline failure"
        }) else { return issue }
        failures.withLock { $0.append(issue.isFailure) }
        return nil
      }

      try await handling.provideScope(for: test, testCase: nil) {
        try await SwiftTestingRuleSession.$testingSession.withValue(session) {
          try await outer.provideScope(for: test, testCase: nil) {
            try await inner.provideScope(for: test, testCase: nil) {
              Issue.record("Unrelated nested baseline failure")
            }
          }
        }
      }

      #expect(failures.withLock { $0 } == [true])
    }
  #endif

  @Test("Nested baseline scope rethrows test error")
  func testError() async throws {
    let outer = BaselineTrait.baseline(Baseline("outer", entries: []))
    let inner = BaselineTrait.baseline(Baseline("inner", entries: []))
    let test = try #require(Test.current)

    await #expect(throws: MockError.failed) {
      try await outer.provideScope(for: test, testCase: nil) {
        try await inner.provideScope(for: test, testCase: nil) {
          throw MockError.failed
        }
      }
    }
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

  private func session(in project: TemporaryProject)
    -> SwiftTestingRuleSession
  {
    SwiftTestingRuleSession(
      id: UUID().uuidString, directory: project.rootURL.path,
      rootPath: project.rootURL.path
    )
  }

  private func violations(
    in project: TemporaryProject,
    name: String = "Screen"
  ) -> Violations<Offender> {
    Violations(rule: "be final", offenders: [Offender(
      description: "class \(name)", name: name,
      location: .start(of: project.fileURL(for: "Screen.swift").path)
    )], checkedCount: 1)
  }

  private enum MockError: Error, Equatable {
    case failed
  }
}
