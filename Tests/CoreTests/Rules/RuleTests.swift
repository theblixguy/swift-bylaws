import Bylaws
import BylawsCore
import BylawsSemantics
import Foundation
import Testing

@Suite("Rules as values")
struct RuleTests {
  @Test("A rule runs its body and erases the offenders")
  func runsAndErases() async throws {
    let rule = Rule(
      "viewmodel-inheritance",
      "ViewModels inherit from BaseViewModel"
    ) {
      try await Self.codebase.classes.suffixed("ViewModel")
        .violations(of: .inherits(from: "BaseViewModel"))
    }

    let violations = try await rule.violations()
    #expect(violations.count == 1)
    let offender = try #require(violations.offenders.first)
    #expect(offender.description.contains("HomeViewModel"))
    #expect(offender.location.fileName == "Screens.swift")
  }

  @Test("A rule declared with a name alone uses the name as its id")
  func nameDoublesAsID() {
    let rule = Rule("Screens stay final") {
      try await Self.codebase.classes.violations(of: .isFinal)
    }
    #expect(rule.id == Rule.ID("Screens stay final"))
    #expect(rule.enforcement == .enforced)
  }

  @Test("A typed body reports findings with no warnings")
  func typedBodyHasNoWarnings() async throws {
    let rule = Rule("Screens stay final") {
      try await Self.codebase.classes.violations(of: .isFinal)
    }

    let findings = try await rule.findings()
    #expect(findings.warnings.isEmpty)
    #expect(findings.violations.count == 1)
  }

  @Test("Findings carry warnings and 'violations()' drops them")
  func findingsCarryWarnings() async throws {
    let location = DeclarationLocation(
      filePath: "/project/Bylaws.swift", line: 3, column: 1, utf8Offset: 0
    )
    let warning = Rule.Warning(
      message: "layer 'Ghost' matched no files",
      location: location
    )
    let rule = Rule(
      Rule.ID("layering"),
      "The declared layering holds",
      enforcement: .enforced,
      location: location
    ) {
      Rule.Findings(
        violations: Violations(rule: "hold", offenders: [], checkedCount: 0),
        warnings: [warning]
      )
    }

    let findings = try await rule.findings()
    #expect(findings.warnings == [warning])
    let violations = try await rule.violations()
    #expect(violations == findings.violations)
  }

  @Test("A failing body produces a rule error that names the rule")
  func wrapsFailures() async {
    let rule = Rule("broken", "Checks a codebase that does not exist") {
      try await Codebase(root: .directory("/nonexistent-bylaws-root"))
        .classes.violations(of: .isFinal)
    }

    await #expect(throws: RuleError.self) {
      try await rule.violations()
    }
  }

  @Test("Erased violations include the rule phrase and counts")
  func erasureKeepsShape() async throws {
    let typed = try await Self.codebase.classes
      .violations(of: .inherits(from: "BaseViewModel"))
    let erased = typed.erased()

    #expect(erased.rule == typed.rule)
    #expect(erased.count == typed.count)
    #expect(erased.checkedCount == typed.checkedCount)
    #expect(
      erased.offenders.map(\.location) == typed.offenders.map(\.location)
    )

    #expect(erased.erased() == erased)
    #expect(erased.offenders.map(\.name) == typed.offenders.map(\.name))
  }

  @Test("Erased violations encode and decode")
  func jsonWritingAndReadingPreservesViolations() async throws {
    let erased = try await Self.codebase.classes
      .violations(of: .isFinal).erased()
    let data = try JSONEncoder().encode(erased)
    let decoded = try JSONDecoder()
      .decode(Violations<Offender>.self, from: data)
    #expect(decoded == erased)
  }

  private static let codebase = Codebase(root: .sources([
    "Sources/App/Screens.swift": """
    class HomeViewModel {}
    final class SettingsViewModel: BaseViewModel {}
    """,
  ]))
}
