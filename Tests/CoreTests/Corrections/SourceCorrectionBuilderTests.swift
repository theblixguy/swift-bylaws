import Bylaws
import BylawsCore
import Foundation
import Testing

@Suite("Correction operations")
struct SourceCorrectionBuilderTests {
  private static let codebase = Codebase(root: .sources([
    "Sources/Models.swift": "class first {}\nclass second {}",
  ]))

  @Test("Operations combine with edit arrays and returned corrections")
  func mixedOperations() async throws {
    let result = try await Self.codebase.classes.violations(of: .isFinal)
      .withFix { context in
        try Replace(
          context.offender.nameSource,
          with: context.offender.name.uppercased()
        )
        [try context.source.slice(0..<0).replacement(with: "final ")]
      }
    let fixes = result.fixes.compactMap(\.self)
    let source = try #require(fixes.first?.edits.first).source.file
    let corrected = try source.replacement(applying: fixes.flatMap(\.edits))

    #expect(corrected
      .replacement == "final class FIRST {}\nfinal class SECOND {}")
    #expect(result.offenders.map(\.name) == ["first", "second"])
  }

  @Test("Named callbacks and explicit returns retain edit-array support")
  func existingCallbacks() async throws {
    let original = try await Self.codebase.classes.violations(of: .isFinal)
    let callback: (FixContext<Class>) async throws
      -> [SourceFix.Edit] = { context in
        [try context.source.slice(0..<0).replacement(with: "final ")]
      }
    let named = try await original.withFix(nil, callback)
    let returned = try await original.withFix { context in
      [try context.source.slice(0..<0).replacement(with: "final ")]
    }
    let empty = try await original.withFix { _ in [] }

    #expect(named.fixes == returned.fixes)
    #expect(named.fixes.compactMap(\.self).flatMap(\.edits)
      .map(\.replacement) == [
        "final ",
        "final ",
      ])
    #expect(empty.fixes == [nil, nil])
  }

  @Test("Fix expressions retain their titles")
  func fixTitles() async throws {
    let declaration = try #require(await Self.codebase.classes.first)
    let fix = SourceFix(
      "Rename",
      edits: [try declaration.nameSource.replacement(with: "Changed")]
    )
    let original = try await Self.codebase.classes.named("first")
      .violations(of: .isFinal)
    let expression = try await original.withFix { _ in fix }
    let callback: (FixContext<Class>) async throws -> SourceFix = { _ in fix }
    let returned = try await original.withFix(nil, callback)
    let correction = try await original.withFix { _ in SourceCorrection(fix) }

    #expect(expression.fixes.first??.title == "Rename")
    #expect(returned.fixes.first??.title == "Rename")
    #expect(correction.fixes.first??.title == "Rename")
  }

  @Test("Replacing a correction clears its earlier failure")
  func replacedFailure() async throws {
    let declaration = try #require(await Self.codebase.classes.first)
    let edit = try declaration.nameSource.replacement(with: "Changed")
    let original = try await Self.codebase.classes.named("first")
      .violations(of: .isFinal)
      .withFix { _ in SourceCorrection.unavailable("Keep the original name.") }
      .erased()
    let updated = try await original.withFix { _ in edit }
    let erased = updated.erased()

    #expect(erased.correctionFailures == [nil])
    #expect(erased.offenders.first?.correctionFailure == nil)
    #expect(erased.offenders.first?.summary == "first")
    #expect(erased.fixes.first??.edits == [edit])
  }

  @Test(
    "First unavailable correction appears in offender and combined findings"
  )
  func firstFailure() async throws {
    let original = Violations(
      rule: "Use final", offenders: [Offender(
        description: "Model",
        location: .start(of: "Model.swift")
      )], checkedCount: 1
    )
    let failed = try await original
      .withFix { _ in SourceCorrection.unavailable("Keep the attached macro.") }
    let combined = Rule.Findings(checks: [failed, original]).violations

    #expect(failed.offenders.first?
      .correctionFailure == "Keep the attached macro.")
    #expect(failed.offenders.first?.summary
      .contains("Keep the attached macro.") == true)
    #expect(combined.correctionFailures == ["Keep the attached macro.", nil])
    #expect(combined.offenders.map(\.correctionFailure) == [
      "Keep the attached macro.",
      nil,
    ])
  }

  @Test("Manual offender failures remain available")
  func manualFailures() {
    let offender = Offender(
      description: "Model", location: .start(of: "Model.swift"),
      correctionFailure: "Keep the attached comment."
    )
    let violations = Violations(
      rule: "Use final",
      offenders: [offender],
      checkedCount: 1
    )

    #expect(violations.correctionFailures == ["Keep the attached comment."])
    #expect(violations.erased()
      .correctionFailures == ["Keep the attached comment."])
  }

  @Test("Decoded correction failures appear in findings")
  func decodedFailures() throws {
    let original = Violations(
      rule: "Use final",
      offenders: [Offender(
        description: "Model",
        location: .start(of: "Model.swift")
      )],
      checkedCount: 1
    )
    var payload = try #require(JSONSerialization
      .jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
    payload["correctionFailures"] = ["Keep the attached macro."]
    let decoded = try JSONDecoder().decode(
      Violations<Offender>.self,
      from: JSONSerialization.data(withJSONObject: payload)
    )
    let findings = Rule.Findings(violations: decoded)

    #expect(findings.checks.first?.offenders.first?
      .correctionFailure == "Keep the attached macro.")
    #expect(findings.violations.offenders.first?.summary
      .contains("Keep the attached macro.") == true)
    #expect(findings.violations
      .correctionFailures == ["Keep the attached macro."])
  }

  @Test("Empty edit corrections differ from absent operations")
  func emptyCorrections() {
    let explicit = SourceCorrection(edits: [])
    let absent = [SourceCorrection]().correction

    #expect(explicit.outcome == .satisfied)
    #expect(explicit.fix?.edits == [])
    #expect(absent.outcome == .notApplicable)
    #expect(absent.fix == nil)
  }

  @Test("Unavailable operation withholds the whole correction")
  func unavailableOperation() async throws {
    let result = try await Self.codebase.classes
      .violations("Use final classes") { declaration in
        try Replace(declaration.nameSource, with: declaration.name.uppercased())
        SourceCorrection.unavailable("The declaration has a dependent macro.")
      }

    #expect(result.checkedCount == 2)
    #expect(result.offenders.map(\.name) == ["first", "second"])
    #expect(result.fixes == [nil, nil])
    #expect(result.correctionFailures == [
      "The declaration has a dependent macro.",
      "The declaration has a dependent macro.",
    ])
  }

  @Test("Explicit correction annotations support conditions and loops")
  func annotatedArray() async throws {
    let result = try await Self.codebase.classes.violations(of: .isFinal)
      .withFix { (context: FixContext<Class>) -> SourceCorrection in
        if context.offender.name == "first" {
          try context.source.slice(0..<0).replacement(with: "final ")
        }
        for part in try context.offender.nameSource.matches(of: /[a-z]+/) {
          part.replacement(with: part.text.uppercased())
        }
      }
    let fixes = result.fixes.compactMap(\.self)
    let source = try #require(fixes.first?.edits.first).source.file

    #expect(try source.replacement(applying: fixes.flatMap(\.edits)).replacement
      == "final class FIRST {}\nclass SECOND {}")
  }

  @Test("Unknown applicability stops each run purpose", arguments: [
    RuleRunPurpose.checkOnly, .proposeCorrections,
  ])
  func unknownApplicability(purpose: RuleRunPurpose) async {
    await #expect(throws: SourceCorrectionError
      .undetermined("The enclosing builder is unknown."))
    {
      try await RuleRunPurpose.$current.withValue(purpose) {
        try await Self.codebase.classes
          .violations("Remove redundant scopes") { declaration in
            try Replace(declaration.nameSource, with: "Renamed")
            SourceCorrection.undetermined("The enclosing builder is unknown.")
          }
      }
    }
  }

  @Test("Unavailable reasons survive erasure filtering and transport")
  func unavailableTransport() async throws {
    let original = try await Self.codebase.classes.violations(of: .isFinal)
      .withFix { _ in
        SourceCorrection.unavailable("Retain the attached comment.")
      }
    let erased = original.erased().erased()
    let filtered = erased.filteringOffenders { $0.name == "second" }
    let combined = Rule.Findings(checks: [filtered, filtered]).violations
    let decoded = try JSONDecoder().decode(
      Violations<Offender>.self, from: JSONEncoder().encode(combined)
    )

    #expect(decoded.offenders.map(\.name) == ["second", "second"])
    #expect(decoded.fixes == [nil, nil])
    #expect(decoded.correctionFailures == [
      "Retain the attached comment.", "Retain the attached comment.",
    ])
    #expect(decoded.offenders.map(\.description) == ["second", "second"])
    #expect(decoded.offenders.map(\.summary) == [
      "second. Correction unavailable: Retain the attached comment.",
      "second. Correction unavailable: Retain the attached comment.",
    ])
  }

  @Test("Nonmatching and satisfied operations keep the check passing")
  func passingOperations() async throws {
    let result = try await Self.codebase.classes
      .violations("Keep names") { declaration in
        SourceCorrection.notApplicable
        try Replace(declaration.nameSource, with: declaration.name)
      }

    #expect(result.checkedCount == 2)
    #expect(result.isEmpty)
    #expect(result.fixes.isEmpty)
    #expect(result.correctionFailures.isEmpty)
  }
}
