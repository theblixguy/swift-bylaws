import Bylaws
import BylawsCore
import BylawsSemantics
import Testing

@Suite("Combined rule results")
struct RuleBuilderTests {
  @Test("Nested result collections preserve warnings and requirements")
  func nestedResults() {
    let location = DeclarationLocation.start(of: "Rules.swift")
    let offender = Offender(description: "Model", location: location)
    let warning = Rule.Warning(
      message: "A check could not read all files.",
      location: location
    )
    let first = Rule.Findings(
      violations: Violations(
        rule: "be final",
        offenders: [offender],
        checkedCount: 1
      ),
      warnings: [warning]
    )
    let second = Violations(
      rule: "be documented",
      offenders: [offender],
      checkedCount: 1
    )

    let findings = RuleResults(RuleResults(first, second))
      .findings(reportedAt: location)

    #expect(findings.warnings == [warning])
    #expect(findings.checks.count == 2)
    #expect(findings.violations.offenders.map(\.requirement) == [
      "be final",
      "be documented",
    ])
  }

  @Test("Rule list builders retain array operations and order")
  func ruleList() async throws {
    let rules = Array {
      Rule("first") { Violations<Offender>(
        rule: "pass",
        offenders: [],
        checkedCount: 1
      ) }
      if true {
        for name in ["second", "third"] {
          Rule(name) { Violations<Offender>(
            rule: "pass",
            offenders: [],
            checkedCount: 1
          ) }
        }
      }
      [Rule("fourth") { Violations<Offender>(
        rule: "pass",
        offenders: [],
        checkedCount: 1
      ) }]
    }

    #expect(rules.map(\.id.rawValue) == ["first", "second", "third", "fourth"])
    #expect(try await rules[0].violations().checkedCount == 1)
  }

  @Test("Layer builders preserve import policies and declaration order")
  func layerList() {
    let names = ["Domain", "Data"]
    let layering = Layering {
      for name in names {
        Layer(name, files: [Glob("Sources/\(name)/**")])
      }
      if true {
        Layer("App", files: ["Sources/App/**"], mayImport: .any)
      }
    }

    #expect(layering.layers.map(\.name) == ["Domain", "Data", "App"])
    #expect(layering.layers.last?.importPolicy == .any)
  }

  @Test("Each failed check retains its requirement")
  func requirements() async throws {
    let app = Codebase(root: .sources(["Model.swift": "class Model {}"]))
    let rule = Rule("models", "Models follow project rules") {
      let classes = try await app.classes
      classes.violations(of: .isFinal)
      classes.violations(of: .hasDocumentation)
    }

    let findings = try await rule.findings()

    #expect(findings.checks.map(\.rule) == [
      "be final",
      "have a documentation comment",
    ])
    #expect(findings.violations.offenders.map(\.requirement) == [
      "be final",
      "have a documentation comment",
    ])
    #expect(findings.violations.checkedCount == 2)
  }

  @Test(
    "Conditional checks and loops preserve execution order",
    arguments: [true, false]
  )
  func controlFlow(includeFinal: Bool) async throws {
    let app = Codebase(root: .sources(["Model.swift": "class Model {}"]))
    let rule = Rule("models") {
      let classes = try await app.classes
      if includeFinal {
        classes.violations(of: .isFinal)
      } else {
        classes.violations(of: .hasDocumentation)
      }
      for name in ["First", "Second"] {
        classes.violations(of: .named(name))
      }
    }

    let findings = try await rule.findings()

    #expect(findings.checks.count == 3)
    #expect(findings.checks.dropFirst().map(\.rule) == [
      "be named 'First'",
      "be named 'Second'",
    ])
  }

  @Test("An empty builder warns about missing checks")
  func empty() async throws {
    let rule = Rule("empty") {}
    let findings = try await rule.findings()

    #expect(findings.checks.isEmpty)
    #expect(findings.warnings.count == 1)
  }

  @Test("An explicit return keeps ordinary closure behaviour")
  func explicitReturn() async throws {
    let app = Codebase(root: .sources(["Model.swift": "class Model {}"]))
    let rule = Rule("models") {
      try await app.classes.violations(of: .isFinal)
    }

    #expect(try await rule.findings().checks.count == 1)
  }

  @Test("Parameter packs combine different result types")
  func mixedResults() async throws {
    let app =
      Codebase(
        root: .sources(["Model.swift": "class Model {}\nfunc load() {}"])
      )
    let classes = try await app.classes
    let functions = try await app.functions
    let results = RuleResults(
      classes.violations(of: .isFinal),
      functions.violations(of: .isAsync)
    )

    let findings = results.findings(reportedAt: .start(of: "Rules.swift"))

    #expect(findings.checks.count == 2)
    #expect(findings.violations.offenders.map(\.name) == ["Model", "load"])
  }
}
