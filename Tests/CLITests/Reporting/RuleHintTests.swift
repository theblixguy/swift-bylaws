import BylawsCore
import BylawsRunner
import BylawsSemantics
import Testing
@testable import bylaws_cli

@Suite("Rule hints in CLI reports")
struct RuleHintTests {
  @Test("Xcode format prints hint beside violation")
  func xcodeHint() throws {
    let output = try render(
      reports: [report(hint: "a view model belongs in Sources/App")],
      diagnostics: [],
      format: .xcode,
      quiet: true
    )

    #expect(
      output
        == "/project/Sources/Home.swift:7:1: error: class HomeViewModel "
        + "violates 'ViewModels inherit from BaseViewModel' "
        + "[viewmodel-inheritance] (a view model belongs in Sources/App)"
    )
  }

  @Test("GitHub format prints hint beside violation")
  func gitHubHint() throws {
    let output = try render(
      reports: [report(hint: "a view model belongs in Sources/App")],
      diagnostics: [],
      format: .github,
      quiet: true
    )

    #expect(
      output
        == "::error file=/project/Sources/Home.swift,line=7::"
        + "class HomeViewModel violates "
        + "'ViewModels inherit from BaseViewModel' "
        + "[viewmodel-inheritance] (a view model belongs in Sources/App)"
    )
  }

  @Test(
    "Rule without hint prints violation alone",
    arguments: [OutputFormat.xcode, .github]
  )
  func withoutHint(format: OutputFormat) throws {
    let output = try render(
      reports: [report(hint: nil)],
      diagnostics: [],
      format: format,
      quiet: true
    )

    #expect(output.hasSuffix("[viewmodel-inheritance]"))
  }

  private let location = DeclarationLocation(
    filePath: "/project/Bylaws.swift",
    line: 4,
    column: 1,
    utf8Offset: 20
  )

  private func report(hint: String?) -> RuleReport {
    let offender = Offender(
      description: "class HomeViewModel",
      name: "HomeViewModel",
      location: DeclarationLocation(
        filePath: "/project/Sources/Home.swift",
        line: 7,
        column: 1,
        utf8Offset: 42
      )
    )
    return RuleReport(
      id: "viewmodel-inheritance",
      name: "ViewModels inherit from BaseViewModel",
      enforcement: .enforced,
      hint: hint,
      location: location,
      violations: Violations(
        rule: "inherit from BaseViewModel",
        offenders: [offender],
        checkedCount: 1
      ),
      warnings: []
    )
  }
}
