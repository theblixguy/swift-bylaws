import BylawsCore
import BylawsInterpreter
import BylawsRunner
import BylawsSemantics
import Testing
@testable import bylaws_cli

@Suite("Rule findings in GitHub output")
struct GitHubRuleRenderingTests {
  @Test("GitHub output uses project-relative paths for rule findings")
  func relativePaths() throws {
    let ruleLocation = DeclarationLocation(
      filePath: "/project/Bylaws.swift",
      line: 9,
      column: 1,
      utf8Offset: 30
    )
    let offenderLocation = DeclarationLocation(
      filePath: "/project/Sources/Home.swift",
      line: 7,
      column: 1,
      utf8Offset: 42
    )
    let reports = [
      RuleReport(
        id: "layers",
        name: "Layers hold",
        enforcement: .enforced,
        hint: "move the type",
        location: ruleLocation,
        violations: Violations(
          rule: "stay in its layer",
          offenders: [Offender(
            description: "class Home",
            name: "Home",
            location: offenderLocation
          )],
          checkedCount: 1
        ),
        warnings: [Rule.Warning(
          message: "target 'CModule' has no files",
          location: ruleLocation
        )]
      ),
      RuleReport(
        id: "empty",
        name: "Nothing matched",
        enforcement: .enforced,
        hint: nil,
        location: ruleLocation,
        violations: Violations(
          rule: "match something",
          offenders: [],
          checkedCount: 0
        ),
        warnings: []
      ),
    ]

    let output = try render(
      reports: reports,
      diagnostics: [],
      format: .github,
      quiet: true,
      rootPath: "/project"
    )

    #expect(output == """
    ::error file=Sources/Home.swift,line=7::class Home violates \
    'Layers hold' [layers] (move the type)
    ::warning file=Bylaws.swift,line=9::Layers hold: target 'CModule' \
    has no files [layers]
    ::warning file=Bylaws.swift,line=9::Nothing matched: the query matched \
    no declarations [empty]
    """)
  }
}
