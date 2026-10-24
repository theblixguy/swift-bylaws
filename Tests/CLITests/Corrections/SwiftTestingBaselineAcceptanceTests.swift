import Bylaws
import BylawsCore
import BylawsInterpreter
import BylawsPaths
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing
@testable import BylawsRunner

@Suite("Collected Swift Testing baseline acceptance")
struct SwiftTestingBaselineAcceptanceTests {
  @Test(
    "Acceptance preserves checks, witnesses, fixes and warnings across reports"
  )
  func multipleChecks() async throws {
    let project = try TemporaryProject(files: [:])
    let first = try swiftTestingCheck(
      ["AcceptedOne", "KeptOne"],
      root: project.rootURL.path
    )
    let second = try swiftTestingCheck(
      ["KeptTwo", "AcceptedTwo"],
      root: project.rootURL.path
    )
    let firstWitness = DeclarationLocation
      .start(of: project.fileURL(for: "First.swift").path)
    let secondWitness = DeclarationLocation
      .start(of: project.fileURL(for: "Second.swift").path)
    let firstCheck = Violations(
      rule: "use first policy", offenders: first.offenders, checkedCount: 7,
      witnesses: [nil, firstWitness], fixes: first.fixes
    )
    let secondCheck = Violations(
      rule: "use second policy", offenders: second.offenders, checkedCount: 11,
      witnesses: [secondWitness, nil], fixes: second.fixes
    )
    let warning = Rule.Warning(
      message: "Source scope is partial",
      location: firstWitness
    )
    let collection = try SwiftTestingRuleResults.collect(from: [
      swiftTestingReport(
        Rule.Findings(checks: [
          firstCheck,
          Violations(rule: "empty check", offenders: [], checkedCount: 3),
        ]),
        accepted: [true, false]
      ),
      swiftTestingReport(
        Rule.Findings(checks: [secondCheck], warnings: [warning]),
        accepted: [false, true]
      ),
    ], alongside: [])
    let collected = try #require(collection.rules.first)
    let full = try await collected.rule.findings()
    let result = try await run(collection, in: project)
    let report = try #require(result.reports.first)

    #expect(full.checks.map(\.checkedCount) == [7, 3, 11])
    #expect(full.violations.offenders.map(\.name) == [
      "AcceptedOne",
      "KeptOne",
      "KeptTwo",
      "AcceptedTwo",
    ])
    #expect(report.violations.offenders.map(\.name) == ["KeptOne", "KeptTwo"])
    #expect(report.violations.offenders.map(\.requirement) == [
      "use first policy",
      "use second policy",
    ])
    #expect(report.violations.witnesses == [firstWitness, secondWitness])
    #expect(report.violations.fixes == [first.fixes[1], second.fixes[0]])
    #expect(report.violations.checkedCount == 21)
    #expect(report.warnings == [warning])
    #expect(result.baselineEntries.count == 4)
  }

  @Test("Equal offender occurrences keep independent acceptance and fixes")
  func duplicateOffenders() async throws {
    let project = try TemporaryProject(files: [:])
    let first = try swiftTestingCheck(["Shared"], root: project.rootURL.path)
    let originalFix = try #require(first.fixes.first ?? nil)
    let source = try #require(originalFix.edits.first).source
    let otherFix = SourceFix(
      "Use public access",
      edits: [source.replacement(with: "public class Shared {}")]
    )
    let witness = DeclarationLocation
      .start(of: project.fileURL(for: "Use.swift").path)
    let second = Violations(
      rule: first.rule, offenders: first.offenders, checkedCount: 1,
      witnesses: [witness], fixes: [otherFix]
    )
    let collection = try SwiftTestingRuleResults.collect(from: [
      swiftTestingReport(first, accepted: [true]),
      swiftTestingReport(second, accepted: [false]),
    ], alongside: [])
    let result = try await run(collection, in: project)
    let violations = try #require(result.reports.first).violations

    #expect(violations.offenders.map(\.name) == ["Shared"])
    #expect(violations.fixes == [otherFix])
    #expect(violations.witnesses == [witness])
    #expect(violations.checkedCount == 2)
  }

  @Test("Accepted parent layout stays inactive around child correction")
  func acceptedParentLayout() async throws {
    let original = "struct Panel {\n  func zebra() {}\n  func alpha() {}\n}"
    let project = try TemporaryProject(files: ["Panel.swift": original])
    let codebase = Codebase(
      root: .directory(project.rootURL.path), including: ["Panel.swift"],
      swiftLanguageMode: .v6
    )
    let parent = try await codebase.syntaxNodes(of: .structDeclaration)
      .violations("Order members") { declaration in
        try declaration.members.replacement {
          declaration.members.sorted { ($0.name ?? "") < ($1.name ?? "") }
        }
      }
    let child = try await codebase.functions.named("zebra")
      .violations(of: .named("finish"))
      .withFix("Rename method") { context in
        try context.offender.nameSource.replacement(with: "finish")
      }
    let collection = try SwiftTestingRuleResults.collect(from: [
      swiftTestingReport(parent, accepted: [true], id: "member-order"),
      swiftTestingReport(child, accepted: [false], id: "method-name"),
    ], alongside: [])

    let result = try await run(collection, in: project)
    let parentReport = try #require(result.reports
      .first { $0.id == "member-order" })
    let childReport = try #require(result.reports
      .first { $0.id == "method-name" })
    let plan = CorrectionPlan.prepare(
      reports: result.reports, rootPath: project.rootURL.path
    )

    #expect(parentReport.violations.isEmpty)
    #expect(parentReport.violations.layoutCandidates.isEmpty)
    #expect(childReport.violations.offenders.map(\.name) == ["zebra"])
    #expect(plan.diagnostics.isEmpty)
    #expect(plan.fixCount == 1)
    #expect(plan.changes.count == 1)
    let changed = try await plan.apply(captures: [])
    #expect(changed == [project.fileURL(for: "Panel.swift").path])
    #expect(try String(
      contentsOf: project.fileURL(for: "Panel.swift"),
      encoding: .utf8
    ) == """
    struct Panel {
      func finish() {}
      func alpha() {}
    }
    """)
  }

  @Test(
    "Accepted offenders remain available for baseline recording and observation"
  )
  func acceptedBaselineEntries() async throws {
    let project = try TemporaryProject(files: [:])
    let check = try swiftTestingCheck(
      ["First", "Second"],
      root: project.rootURL.path
    )
    let entries = [
      Baseline.Entry(rule: "final", declaration: "First", file: "First.swift"),
      Baseline.Entry(
        rule: "final",
        declaration: "Second",
        file: "Second.swift"
      ),
    ]
    let baseline = project.fileURL(for: "Bylaws.baseline.swift")
    try BaselineFile.render(name: "accepted", entries: entries)
      .write(to: baseline, atomically: true, encoding: .utf8)
    let warning = Rule.Warning(
      message: "Source scope is partial",
      location: .start(of: baseline.path)
    )
    let collection = try SwiftTestingRuleResults.collect(from: [
      swiftTestingReport(
        Rule.Findings(violations: check, warnings: [warning]),
        accepted: [true, true]
      ),
    ], alongside: [])
    let result = try await RuleRunner.run(
      RuleRunConfiguration(
        root: LexicalFilePath(project.rootURL.path),
        baseline: baseline.path
      ),
      loaded: LoadedRuleProgram(
        rootPath: project.rootURL.path,
        program: RuleProgram(loadedRules: [], diagnostics: [])
      ),
      testRules: collection
    )
    let report = try #require(result.reports.first)

    #expect(result.baselineEntries == Set(entries))
    #expect(result.diagnostics.isEmpty)
    #expect(result.outcome == .passed)
    #expect(report.violations.isEmpty)
    #expect(report.violations.checkedCount == 2)
    #expect(report.warnings == [warning])
  }

  @Test(
    "Acceptance follows rule identity through sorting and selection",
    arguments: [false, true],
    [false, true]
  )
  func selectedRules(reversed: Bool, useOnly: Bool) async throws {
    let project = try TemporaryProject(files: [:])
    let alpha = try swiftTestingCheck(["Alpha"], root: project.rootURL.path)
    let zeta = try swiftTestingCheck(["Zeta"], root: project.rootURL.path)
    let reports = [
      swiftTestingReport(alpha, accepted: [true], id: "alpha"),
      swiftTestingReport(zeta, accepted: [false], id: "zeta"),
    ]
    let ordered = if reversed { Array(reports.reversed()) } else { reports }
    let collection = try SwiftTestingRuleResults.collect(
      from: ordered,
      alongside: []
    )
    let result = try await RuleRunner.run(
      RuleRunConfiguration(
        root: LexicalFilePath(project.rootURL.path),
        only: useOnly ? ["zeta"] : [], skip: useOnly ? [] : ["alpha"]
      ),
      loaded: LoadedRuleProgram(
        rootPath: project.rootURL.path,
        program: RuleProgram(loadedRules: [], diagnostics: [])
      ),
      testRules: collection
    )

    #expect(result.reports.map(\.id) == ["zeta"])
    let violations = try #require(result.reports.first).violations
    #expect(violations.offenders.map(\.name) == ["Zeta"])
    #expect(violations.fixes == zeta.fixes)
    #expect(result.baselineEntries == [Baseline.Entry(
      rule: "zeta",
      declaration: "Zeta",
      file: "Zeta.swift"
    )])
  }

  @Test(
    "Collection rejects missing or extra acceptance values",
    arguments: [[], [false, true]],
    [false, true]
  )
  func malformedAcceptance(accepted: [Bool], portable: Bool) throws {
    let check = try swiftTestingCheck(["First"])
    let origin = Rule.Origin(filePath: "/project/Bylaws.swift", ruleID: "final")
    var rule = Rule("final", "Classes are final") { check }
    rule.origin = origin

    #expect(throws: SwiftTestingRuleSessionError
      .malformedReport(
        "The baseline acceptance count must equal the offender count"
      ))
    {
      try SwiftTestingRuleResults.collect(
        from: [swiftTestingReport(
          check,
          accepted: accepted,
          origin: portable ? origin : nil
        )],
        alongside: portable ? [rule] : []
      )
    }
  }

  private func run(
    _ collection: SwiftTestingRuleResults.Collection,
    in project: TemporaryProject
  ) async throws -> RuleRunResult {
    try await RuleRunner.run(
      RuleRunConfiguration(root: LexicalFilePath(project.rootURL.path)),
      loaded: LoadedRuleProgram(
        rootPath: project.rootURL.path,
        program: RuleProgram(loadedRules: [], diagnostics: [])
      ),
      testRules: collection
    )
  }
}
