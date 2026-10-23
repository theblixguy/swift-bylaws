import BylawsCore
import BylawsInterpreter
import BylawsPaths
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing
@testable import BylawsRunner

@Suite("Swift Testing rule result collection")
struct SwiftTestingRuleResultsTests {
  @Test("Portable overrides retain shared rule IDs during collection")
  func portableOverrides() throws {
    let check = try swiftTestingCheck(["First"])
    let root = rule(
      check,
      origin: .init(filePath: "/project/Bylaws.swift", ruleID: "final")
    )
    let child = rule(
      check,
      origin: .init(filePath: "/project/Child/Bylaws.swift", ruleID: "final")
    )

    let collection = try SwiftTestingRuleResults.collect(
      from: [],
      alongside: [root, child]
    )

    #expect(collection.rules.isEmpty)
    #expect(collection.acceptedPortableOffenders.isEmpty)
  }

  @Test("Portable rule acceptance follows exact origin and offender")
  func portableAcceptance() async throws {
    let project = try TemporaryProject(files: [:])
    let check = try swiftTestingCheck(
      ["First", "Second"],
      root: project.rootURL.path
    )
    let rootOrigin = Rule.Origin(
      filePath: project.fileURL(for: "Bylaws.swift").path, ruleID: "final"
    )
    let childOrigin = Rule.Origin(
      filePath: project.fileURL(for: "Child/Bylaws.swift").path, ruleID: "final"
    )
    let root = rule(check, origin: rootOrigin)
    let child = rule(check, origin: childOrigin)
    let report = swiftTestingReport(
      check,
      accepted: [true, false],
      origin: rootOrigin
    )
    let collection = try SwiftTestingRuleResults.collect(
      from: [report], alongside: [root, child]
    )
    let program = RuleProgram(
      loadedRules: [root, child].map(RuleProgram.LoadedRule.init(unscoped:)),
      diagnostics: []
    )

    let result = try await RuleRunner.run(
      RuleRunConfiguration(root: LexicalFilePath(project.rootURL.path)),
      loaded: LoadedRuleProgram(
        rootPath: project.rootURL.path,
        program: program
      ),
      testRules: collection
    )

    #expect(collection.rules.isEmpty)
    #expect(collection
      .acceptedPortableOffenders[rootOrigin] == [check.offenders[0]])
    #expect(collection.acceptedPortableOffenders[childOrigin] == nil)
    try #require(result.reports.count == 2)
    #expect(result.reports[0].violations.offenders.map(\.name) == ["Second"])
    #expect(result.reports[0].violations.fixes == [check.fixes[1]])
    #expect(result.reports[1].violations.offenders.map(\.name) == [
      "First",
      "Second",
    ])
    #expect(result.reports[1].violations.fixes == check.fixes)
    #expect(result.outcome == .violations)
    #expect(result.baselineEntries.count == 2)
  }

  @Test(
    "Swift Testing acceptance stays aligned across parameter reports and fixes"
  )
  func baselineAcceptance() async throws {
    let project = try TemporaryProject(files: [:])
    let first = try swiftTestingCheck(
      ["First", "Second"],
      root: project.rootURL.path
    )
    let second = try swiftTestingCheck(["Third"], root: project.rootURL.path)
    let collection = try SwiftTestingRuleResults.collect(
      from: [
        swiftTestingReport(first, accepted: [true, false]),
        swiftTestingReport(second, accepted: [false]),
      ],
      alongside: []
    )
    let program = RuleProgram(loadedRules: [], diagnostics: [])

    let result = try await RuleRunner.run(
      RuleRunConfiguration(root: LexicalFilePath(project.rootURL.path)),
      loaded: LoadedRuleProgram(
        rootPath: project.rootURL.path,
        program: program
      ),
      testRules: collection
    )

    #expect(collection.rules.count == 1)
    let violations = try #require(result.reports.first).violations
    #expect(violations.offenders.map(\.name) == ["Second", "Third"])
    #expect(violations.fixes == [first.fixes[1], second.fixes[0]])
    #expect(result.baselineEntries.count == 3)
  }

  @Test("Matching portable ID with another origin rejects Swift Testing rule")
  func originMismatch() throws {
    let check = try swiftTestingCheck(["First"])
    let portable = rule(
      check,
      origin: .init(filePath: "/project/Bylaws.swift", ruleID: "final")
    )

    #expect(throws: CaptureError.self) {
      try SwiftTestingRuleResults.collect(
        from: [swiftTestingReport(
          check,
          accepted: [false],
          origin: .init(filePath: "/other/Bylaws.swift", ruleID: "final")
        )],
        alongside: [portable]
      )
    }
  }

  @Test("Combined parameter reports reject checked-count overflow")
  func checkedCountOverflow() throws {
    let reports = [Int.max, 1].map {
      swiftTestingReport(
        Violations<Offender>(rule: "be final", offenders: [], checkedCount: $0),
        accepted: []
      )
    }

    let error = try #require(throws: CaptureError.self) {
      try SwiftTestingRuleResults.collect(from: reports, alongside: [])
    }

    #expect(error.description.contains("final"))
    #expect(error.description.contains("combined checked count"))
  }

  @Test("Combined parameter reports retain largest representable checked count")
  func checkedCountBoundary() async throws {
    let reports = [Int.max - 1, 1].map {
      swiftTestingReport(
        Violations<Offender>(rule: "be final", offenders: [], checkedCount: $0),
        accepted: []
      )
    }

    let collection = try SwiftTestingRuleResults.collect(
      from: reports, alongside: []
    )
    let collected = try #require(collection.rules.first)
    let violations = try await collected.rule.violations()

    #expect(violations.checkedCount == Int.max)
    #expect(violations.isEmpty)
  }

  private enum DefinitionChange: CaseIterable {
    case stable, test, origin
  }

  @Test(
    "Verification retains Swift Testing rule definition",
    arguments: DefinitionChange.allCases
  )
  private func verificationDefinition(_ change: DefinitionChange) throws {
    let previous = swiftTestingReport(
      try swiftTestingCheck(["First"]), accepted: [false],
      origin: .init(filePath: "/project/Bylaws.swift", ruleID: "final")
    )
    let current = swiftTestingReport(
      try swiftTestingCheck([]), accepted: [],
      origin: change == .origin ? .init(
        filePath: "/other/Bylaws.swift",
        ruleID: "final"
      ) : previous
        .origin,
      testID: change == .test ? "another-test" : previous.testID
    )
    let run = run(reports: [current])

    if change == .stable {
      let reports = try SwiftTestingRuleResults.reports(
        from: run,
        verifying: [previous]
      )
      #expect(reports.count == 1)
      #expect(reports[0].findings.violations.offenders.isEmpty)
    } else {
      let error = try #require(throws: CaptureError.self) {
        try SwiftTestingRuleResults.reports(from: run, verifying: [previous])
      }
      #expect(
        error.description == "Swift Testing rule 'final' did not repeat a check during verification. Report each check when it passes and keep its test and metadata stable"
      )
    }
  }

  @Test("Missing report cannot pass verification", arguments: [false, true])
  func missingReport(hasRun: Bool) throws {
    let previous = swiftTestingReport(
      try swiftTestingCheck(["First"]),
      accepted: [false]
    )
    let current = hasRun ? run() : nil

    #expect(throws: CaptureError.self) {
      try SwiftTestingRuleResults.reports(from: current, verifying: [previous])
    }
  }

  @Test(
    "Verification matches each repeated report once",
    arguments: [1, 2]
  )
  func repeatedVerificationReports(currentCount: Int) throws {
    let previous = try ["First", "Second"].map {
      swiftTestingReport(try swiftTestingCheck([$0]), accepted: [false])
    }
    let empty = swiftTestingReport(try swiftTestingCheck([]), accepted: [])
    let current = run(reports: Array(repeating: empty, count: currentCount))

    if currentCount == 1 {
      let error = try #require(throws: CaptureError.self) {
        try SwiftTestingRuleResults.reports(from: current, verifying: previous)
      }
      #expect(
        error.description == "Swift Testing rule 'final' did not repeat a check during verification. Report each check when it passes and keep its test and metadata stable"
      )
    } else {
      let reports = try SwiftTestingRuleResults.reports(
        from: current, verifying: previous
      )

      #expect(reports.count == 2)
      for report in reports {
        #expect(report.findings.violations.isEmpty)
      }
    }
  }

  @Test("Verification matches reordered distinct reports")
  func reorderedVerificationReports() throws {
    let previous = try ["first", "second"].map { id in
      swiftTestingReport(
        try swiftTestingCheck(["Screen"]), accepted: [false],
        id: Rule.ID(id), testID: id
      )
    }
    let empty = try swiftTestingCheck([])
    let current = previous.reversed().map {
      swiftTestingReport(empty, accepted: [], id: $0.ruleID, testID: $0.testID)
    }

    let reports = try SwiftTestingRuleResults.reports(
      from: run(reports: current), verifying: previous
    )

    #expect(reports.map(\.ruleID) == ["second", "first"])
    for report in reports {
      #expect(report.findings.violations.isEmpty)
    }
  }

  private func rule(
    _ check: Violations<Offender>,
    origin: Rule.Origin
  ) -> Rule {
    var rule = Rule("final", "Classes are final") { check }
    rule.origin = origin
    return rule
  }

  private func run(
    reports: [SwiftTestingRuleReport] = []
  ) -> SwiftPMTestRun {
    SwiftPMTestRun(
      reports: reports, captures: [],
      protectedSourcePaths: [], packageRootPath: "/project",
      indexStorePath: nil
    )
  }
}
