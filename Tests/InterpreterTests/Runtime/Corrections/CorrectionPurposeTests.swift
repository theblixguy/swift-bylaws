import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Testing

@Suite("Portable correction purpose")
struct CorrectionPurposeTests {
  @Test("Check-only skips a throwing fix callback")
  func skipsFixes() async throws {
    let project = try correctionProject(ruleBody: """
    try await app.classes.violations(of: .isFinal).withFix { context in
      try context.source.slice(999..<1000).replacement(with: "Updated")
    }
    """)
    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)
    let findings = try await RuleRunPurpose.$current.withValue(.checkOnly) {
      try await rule.findings()
    }

    #expect(findings.violations.checkedCount == 1)
    #expect(findings.violations.offenders.map(\.name) == ["Model"])
    #expect(findings.violations.fixes == [nil])
    await #expect(throws: RuleError.self) {
      try await RuleRunPurpose.$current.withValue(.proposeCorrections) {
        try await rule.findings()
      }
    }
  }

  @Test(
    "Formatting checks detect failures in both purposes",
    arguments: [RuleRunPurpose.checkOnly, .proposeCorrections]
  )
  func detectsChanges(purpose: RuleRunPurpose) async throws {
    let project = try correctionProject(ruleBody: """
    try await app.classes.violations("Use current name") { declaration in
      try declaration.nameSource.replacement(with: "Updated")
    }
    """)
    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)
    let findings = try await RuleRunPurpose.$current.withValue(purpose) {
      try await rule.findings()
    }

    #expect(findings.violations.checkedCount == 1)
    #expect(findings.violations.offenders.map(\.name) == ["Model"])
    if purpose == .checkOnly {
      #expect(findings.violations.fixes == [nil])
    } else {
      let fix = try #require(findings.violations.fixes.first ?? nil)
      #expect(fix.edits.map(\.replacement) == ["Updated"])
    }
  }

  @Test(
    "Formatting callbacks keep their throwing effects",
    arguments: [RuleRunPurpose.checkOnly, .proposeCorrections]
  )
  func detectorErrors(purpose: RuleRunPurpose) async throws {
    let project = try correctionProject(ruleBody: """
    try await app.classes.violations("Use current name") { declaration in
      try declaration.nameSource.slice(999..<1000).replacement(with: "Updated")
    }
    """)
    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)

    await #expect(throws: RuleError.self) {
      try await RuleRunPurpose.$current.withValue(purpose) {
        try await rule.findings()
      }
    }
  }

  @Test(
    "Passing formatting plans remain available when requested",
    arguments: [RuleRunPurpose.checkOnly, .proposeCorrections]
  )
  func passingPlans(purpose: RuleRunPurpose) async throws {
    let project = try correctionProject(ruleBody: """
    try await app.classes.violations("Keep attributes") { declaration in
      try declaration.attributes.replacement {
        Line { declaration.attributes }
      }
    }
    """)
    try project.write(
      "@MainActor @Observable\nclass Model {}", to: "Sources/Model.swift"
    )
    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)
    let findings = try await RuleRunPurpose.$current.withValue(purpose) {
      try await rule.findings()
    }

    #expect(findings.violations.checkedCount == 1)
    #expect(findings.violations.isEmpty)
    if purpose == .checkOnly {
      #expect(findings.violations.layoutCandidates.isEmpty)
    } else {
      let candidate = try #require(findings.violations.layoutCandidates.first)
      #expect(findings.violations.layoutCandidates.count == 1)
      #expect(candidate.replacement == "@MainActor @Observable\n")
    }
  }
}
