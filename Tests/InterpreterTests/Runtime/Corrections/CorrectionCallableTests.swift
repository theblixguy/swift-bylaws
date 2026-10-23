import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import Testing

@Suite("Portable correction callables")
struct CorrectionCallableTests {
  @Test(
    "Named correction functions retain external argument labels",
    arguments: [false, true]
  )
  func namedFunction(attachesToViolations: Bool) async throws {
    let input = attachesToViolations ? "FixContext<Class>" : "Class"
    let declaration = attachesToViolations ? "value.offender" : "value"
    let check =
      attachesToViolations
        ? "try await app.classes.violations(of: .isFinal).withFix(correction)"
        : "try await app.classes.violations(\"Rename store\", changes: correction)"
    let project = try correctionProject(
      declarations: """
      func correction(input value: \(input)) throws -> [SourceFix.Edit] {
        [try \(declaration).nameSource.replacement(with: "Renamed")]
      }
      """,
      ruleBody: check
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let fix = try #require(findings.violations.fixes.first ?? nil)

    #expect(findings.violations.count == 1)
    #expect(fix.edits.map(\.replacement) == ["Renamed"])
    #expect(fix.edits.map(\.source.text) == ["Model"])
  }
}
