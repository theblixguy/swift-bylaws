import BylawsCore
import BylawsRunner
import BylawsSemantics
import Foundation
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
      output == "/project/Sources/Home.swift:7:1: error: class HomeViewModel "
        + "violates 'ViewModels inherit from BaseViewModel' "
        + "[viewmodel-inheritance] (a view model belongs in Sources/App)"
        + "\n/project/Bylaws.swift:4:1: note: "
        + "rule 'viewmodel-inheritance' is declared here"
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
      output == "::error file=/project/Sources/Home.swift,line=7::"
        + "class HomeViewModel violates "
        + "'ViewModels inherit from BaseViewModel' "
        + "[viewmodel-inheritance] (a view model belongs in Sources/App)"
        + "\n::notice file=/project/Bylaws.swift,line=4::"
        + "rule 'viewmodel-inheritance' is declared here"
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

    #expect(output.contains("[viewmodel-inheritance]\n"))
    #expect(output.hasSuffix("rule 'viewmodel-inheritance' is declared here"))
  }

  @Test(
    "Declaration location appears once per rule",
    arguments: [OutputFormat.xcode, .github]
  )
  func declarationLocationAppearsOnce(format: OutputFormat) throws {
    let output = try render(
      reports: [report(hint: nil), report(hint: nil)],
      diagnostics: [],
      format: format,
      quiet: true
    )

    #expect(output.components(separatedBy: "is declared here").count == 2)
  }

  @Test("JSON rule entry carries its declaration location")
  func jsonRuleLocation() throws {
    let output = try render(
      reports: [report(hint: nil)],
      diagnostics: [],
      format: .json,
      quiet: true,
      rootPath: "/project"
    )

    let value = try #require(
      JSONSerialization.jsonObject(with: Data(output.utf8))
        as? [String: Any]
    )
    let rules = try #require(value["rules"] as? [[String: Any]])
    let rule = try #require(rules.first)
    #expect(rule["path"] as? String == "Bylaws.swift")
    #expect(rule["line"] as? Int == 4)
    #expect(rule["column"] as? Int == 1)
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
