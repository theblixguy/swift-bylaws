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
    let check = try check(["First"])
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
    let check = try check(["First", "Second"], root: project.rootURL.path)
    let rootOrigin = Rule.Origin(
      filePath: project.fileURL(for: "Bylaws.swift").path, ruleID: "final"
    )
    let childOrigin = Rule.Origin(
      filePath: project.fileURL(for: "Child/Bylaws.swift").path, ruleID: "final"
    )
    let root = rule(check, origin: rootOrigin)
    let child = rule(check, origin: childOrigin)
    let report = report(check, accepted: [true, false], origin: rootOrigin)
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
      acceptedPortableOffenders: collection.acceptedPortableOffenders
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
    let first = try check(["First", "Second"], root: project.rootURL.path)
    let second = try check(["Third"], root: project.rootURL.path)
    let collection = try SwiftTestingRuleResults.collect(
      from: [
        report(first, accepted: [true, false]),
        report(second, accepted: [false]),
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
      additionalRules: collection.rules,
      acceptedTestOffenders: collection.acceptedOffenders
    )

    #expect(collection.rules.count == 1)
    #expect(collection.acceptedOffenders["final"] == [true, false, false])
    let violations = try #require(result.reports.first).violations
    #expect(violations.offenders.map(\.name) == ["Second", "Third"])
    #expect(violations.fixes == [first.fixes[1], second.fixes[0]])
    #expect(result.baselineEntries.count == 3)
  }

  @Test("Matching portable ID with another origin rejects Swift Testing rule")
  func originMismatch() throws {
    let check = try check(["First"])
    let portable = rule(
      check,
      origin: .init(filePath: "/project/Bylaws.swift", ruleID: "final")
    )

    #expect(throws: CaptureError.self) {
      try SwiftTestingRuleResults.collect(
        from: [report(
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
      report(
        Violations(rule: "be final", offenders: [], checkedCount: $0),
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
      report(
        Violations(rule: "be final", offenders: [], checkedCount: $0),
        accepted: []
      )
    }

    let collection = try SwiftTestingRuleResults.collect(
      from: reports, alongside: []
    )
    let rule = try #require(collection.rules.first)
    let violations = try await rule.violations()

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
    let previous = report(
      try check(["First"]), accepted: [false],
      origin: .init(filePath: "/project/Bylaws.swift", ruleID: "final")
    )
    let current = report(
      try check([]), accepted: [],
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
      #expect(throws: CaptureError.self) {
        try SwiftTestingRuleResults.reports(from: run, verifying: [previous])
      }
    }
  }

  @Test("Missing report cannot pass verification", arguments: [false, true])
  func missingReport(hasRun: Bool) throws {
    let previous = report(try check(["First"]), accepted: [false])
    let current = hasRun ? run() : nil

    #expect(throws: CaptureError.self) {
      try SwiftTestingRuleResults.reports(from: current, verifying: [previous])
    }
  }

  private func check(
    _ names: [String], root: String = "/virtual"
  ) throws -> Violations<Offender> {
    let files = try names.map { name in
      try FileCollector.collect(
        source: "class \(name) {}",
        path: root + "/\(name).swift"
      )
    }
    return try Violations(
      rule: "be final",
      offenders: zip(names, files).map { name, file in
        Offender(description: name, name: name, location: .start(of: file.path))
      },
      checkedCount: names.count,
      witnesses: Array(repeating: nil, count: names.count),
      fixes: files.map { file in
        SourceFix(
          "Add final",
          edits: [try file.source.replacement(with: "final " + file.sourceText)]
        )
      }
    )
  }

  private func rule(
    _ check: Violations<Offender>,
    origin: Rule.Origin
  ) -> Rule {
    var rule = Rule("final", "Classes are final") { check }
    rule.origin = origin
    return rule
  }

  private func report(
    _ check: Violations<Offender>, accepted: [Bool], origin: Rule.Origin? = nil,
    testID: String = "test"
  ) -> SwiftTestingRuleReport {
    SwiftTestingRuleReport(
      sessionID: "session", testID: testID, ruleID: "final",
      name: "Classes are final",
      enforcement: .enforced, hint: nil,
      location: .start(of: "/project/Tests/Rules.swift"),
      findings: Rule.Findings(violations: check), baselineAccepted: accepted,
      origin: origin
    )
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
