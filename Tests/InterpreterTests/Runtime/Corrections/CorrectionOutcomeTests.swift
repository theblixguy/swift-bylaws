import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable correction outcomes")
struct CorrectionOutcomeTests {
  @Test("Stored corrections combine with operation builders", arguments: [
    "SourceCorrection(edits: [try context.offender.nameSource.replacement(with: \"Other\")])",
    "SourceCorrection(combining: [try Replace(context.offender.nameSource, with: \"Other\").correction])",
    "let operation = try Replace(context.offender.nameSource, with: \"Other\"); if operation.correction.outcome == .violation && operation.correction.reason == nil { operation }",
    "let operation = try Replace(context.offender.nameSource, with: \"Other\"); if let fix = try operation.correction.preparedFix() { SourceCorrection(fix) }",
  ])
  func storedCorrections(body: String) async throws {
    let project = try correctionProject(ruleBody: """
    try await app.classes.violations(of: .isFinal).withFix { context in
      \(body)
    }
    """)
    let program = try await loadedProgram(in: project)
    let result = try await #require(program.rules.first).findings().violations

    #expect(result.offenders.map(\.name) == ["Model"])
    #expect(result.fixes.compactMap(\.self).flatMap(\.edits)
      .map(\.replacement) == ["Other"])
  }

  @Test("Correction arrays retain edits", arguments: [
    "[try Replace(context.offender.nameSource, with: \"Other\")].correction",
    "[try context.offender.nameSource.replacement(with: \"Other\")].correction",
    "[[try Replace(context.offender.nameSource, with: \"Other\")]].correction",
  ])
  func correctionArrays(expression: String) async throws {
    let project = try correctionProject(ruleBody: """
    try await app.classes.violations(of: .isFinal).withFix { context in
      \(expression)
    }
    """)
    let program = try await loadedProgram(in: project)
    let result = try await #require(program.rules.first).findings().violations

    #expect(result.fixes.compactMap(\.self).flatMap(\.edits)
      .map(\.replacement) == ["Other"])
  }

  @Test("Empty edit constructor retains satisfied outcome and fix")
  func emptyEdits() async throws {
    let project = try correctionProject(ruleBody: """
    try await app.classes.violations(of: .isFinal).withFix { context in
      let correction = SourceCorrection(edits: [])
      if correction.outcome == .satisfied && correction.fix != nil {
        try Replace(context.offender.nameSource, with: "Other")
      }
    }
    """)
    let program = try await loadedProgram(in: project)
    let result = try await #require(program.rules.first).findings().violations

    #expect(result.fixes.compactMap(\.self).flatMap(\.edits)
      .map(\.replacement) == ["Other"])
  }

  @Test("Non-correction arrays fail during compilation")
  func nonCorrectionArray() async throws {
    let project = try correctionProject(ruleBody: """
    try await app.classes.violations(of: .isFinal).withFix { context in
      ["Other"].correction
    }
    """)
    let program = await RuleProgram
      .loaded(fromFiles: [project.fileURL(for: "ProjectRules.swift").path])

    #expect(program.errors.map(\.message)
      .contains("Array must contain source corrections"))
  }

  @Test("Unavailable operation keeps violation and withholds other edits")
  func unavailableOperation() async throws {
    let project = try correctionProject(ruleBody: """
    try await app.classes.violations("Use another name") { declaration in
      try Replace(declaration.nameSource, with: "Other")
      SourceCorrection.unavailable("Retain the attached macro.")
    }
    """)
    let program = try await loadedProgram(in: project)
    let result = try await #require(program.rules.first).findings().violations

    #expect(result.offenders.map(\.name) == ["Model"])
    #expect(result.fixes == [nil])
    #expect(result.correctionFailures == ["Retain the attached macro."])
    #expect(result.offenders.first?
      .correctionFailure == "Retain the attached macro.")
  }

  @Test("Nonmatching operations leave the check passing")
  func nonmatching() async throws {
    let project = try correctionProject(ruleBody: """
    try await app.classes.violations("Keep names") { declaration in
      SourceCorrection.notApplicable
      SourceCorrection.satisfied
    }
    """)
    let program = try await loadedProgram(in: project)
    let result = try await #require(program.rules.first).findings().violations

    #expect(result.checkedCount == 1)
    #expect(result.isEmpty)
    #expect(result.fixes.isEmpty)
  }
}
