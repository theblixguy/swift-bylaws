import BylawsCore
import BylawsRunner
import BylawsSemantics
import Testing
@testable import bylaws_cli

@Suite("Combined rule reports")
struct CombinedRuleReportTests {
  @Test(
    "Each output format retains the individual check requirements",
    arguments: [OutputFormat.xcode, .github, .json, .sarif]
  )
  func requirements(format: OutputFormat) throws {
    let location = DeclarationLocation.start(of: "/project/Sources/Model.swift")
    let offender = Offender(
      description: "class Model",
      name: "Model",
      location: location
    )
    let findings = Rule.Findings(checks: [
      Violations(rule: "be final", offenders: [offender], checkedCount: 1),
      Violations(
        rule: "have a documentation comment",
        offenders: [offender],
        checkedCount: 1
      ),
    ])
    let report = RuleReport(
      id: "models",
      name: "Models follow project rules",
      enforcement: .enforced,
      hint: nil,
      location: rulesFileLocation(),
      violations: findings.violations,
      warnings: []
    )

    let output = try render(reports: [report], format: format, quiet: true)

    #expect(output.contains("be final"))
    #expect(output.contains("have a documentation comment"))
  }
}
