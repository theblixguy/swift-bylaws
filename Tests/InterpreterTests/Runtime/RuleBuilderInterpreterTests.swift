import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable rule builders")
struct RuleBuilderInterpreterTests {
  @Test("Each generated rule keeps its loop value after the list is built")
  func loopCaptures() async throws {
    let project = try TemporaryProject(files: [
      "ProjectRules.swift": #"""
      import Bylaws
      let app = Codebase(including: ["Sources/**"])
      let name = "Outside"
      let projectRules = Array {
        for name in ["First", "Second"] {
          Rule(name) {
            try await app.classes.named(name).violations(of: .isFinal)
          }
        }
      }
      """#,
      "Sources/Models.swift": "class First {}\nclass Second {}\nclass Outside {}",
    ])
    let program = try await loadedProgram(in: project)

    let first = try await program.rules[0].violations()
    let second = try await program.rules[1].violations()

    #expect(first.offenders.map(\.name) == ["First"])
    #expect(second.offenders.map(\.name) == ["Second"])
  }

  @Test("Builders reject values that are not checks", arguments: [
    "true",
    "try await app.classes",
    "try await app.classes.violations(of: Matcher<Class>.all(\\.functions, matching: .isFinal))",
    "try await app.classes.violations(of: Matcher<Class>.all(\\.genericParameters, matching: Matcher<GenericParameter>(\"have a name\") { $0.name == \"T\" }))",
  ])
  func rejectedCheck(expression: String) async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      import Bylaws
      let app = Codebase(including: ["Sources/**"])
      let rules: [Rule] = [Rule("check") { \(expression) }]
      """,
      "Sources/Model.swift": "class Model {}",
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)

    #expect(!program.errors.isEmpty)
  }

  @Test("Boolean constructors and negated member matchers retain failures")
  func matcherComposition() async throws {
    let project = try TemporaryProject(files: [
      "ProjectRules.swift": #"""
      import Bylaws
      let app = Codebase(including: ["Sources/**"])
      let rules: [Rule] = [Rule("members") {
        let classes = try await app.classes
        classes.violations(of: Matcher<Class>(\.isFinal))
        classes.violations(of: Matcher<Class>.none(\.functions, matching: .isAsync))
      }]
      """#,
      "Sources/Model.swift": "class Model {\n  func load() async {}\n}",
    ])
    let program = try await loadedProgram(in: project)

    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.offenders.map(\.location.line) == [1, 2])
    #expect(findings.checks.last?
      .rule == "not have any selected members be async")
  }

  @Test("Rule and layer list builders work together")
  func lists() async throws {
    let project = try TemporaryProject(files: [
      "ProjectRules.swift": #"""
      import Bylaws
      let app = Codebase(including: ["Sources/**"])
      let layers = Layering {
        for name in ["Domain", "Data"] {
          Layer(name, files: ["Sources/" + name + "/**"])
        }
        if true {
          Layer("App", files: ["Sources/App/**"], mayImport: .any)
        }
      }
      let rules = Array {
        Rule("layers") { try await app.checkLayering(layers) }
        for name in ["first", "second"] {
          Rule(name) {
            let classes = try await app.classes
            RuleResults(classes.violations(of: .isFinal), classes.violations(of: .hasDocumentation))
          }
        }
      }
      """#,
      "Sources/Domain/Model.swift": "class Model {}",
      "Sources/Data/Store.swift": "class Store {}",
      "Sources/App/App.swift": "class App {}",
    ])
    let program = try await loadedProgram(in: project)

    let findings = try await program.rules[1].findings()

    #expect(program.rules.map(\.id.rawValue) == ["layers", "first", "second"])
    #expect(findings.checks.count == 2)
    #expect(findings.violations.count == 6)
    #expect(try await program.rules[0].violations().isEmpty)
  }

  @Test("Each expression contributes its check and source location")
  func combinedChecks() async throws {
    let project = try TemporaryProject(files: [
      "ProjectRules.swift": #"""
      import Bylaws
      let app = Codebase(including: ["Sources/**"])
      let rules: [Rule] = [
        Rule("members") {
          let classes = try await app.classes
          classes.violations(of: \.isFinal)
          classes.violations(of: Matcher<Class>.all(\.functions, matching: .isAsync))
          if false {
            classes.violations(of: .hasDocumentation)
          } else {
            for name in ["Model", "Other"] {
              classes.named(name).violations(matching: Matcher<Class>.any(\.functions, matching: .isAsync))
            }
          }
        }
      ]
      """#,
      "Sources/Model.swift": """
      class Model {
        func first() async {}
        func second() {}
      }
      """,
    ])
    let program = try await loadedProgram(in: project)

    let findings = try await #require(program.rules.first).findings()

    #expect(findings.checks.count == 4)
    #expect(findings.violations.offenders.map(\.location.line) == [1, 3, 2])
    #expect(findings.violations.offenders.allSatisfy { $0.requirement != nil })
  }

  @Test("An empty builder reports that no checks ran")
  func emptyBody() async throws {
    let project = try TemporaryProject(files: [
      "ProjectRules.swift": """
      import Bylaws
      let rules: [Rule] = [Rule("empty") {}]
      """,
    ])
    let program = try await loadedProgram(in: project)

    let findings = try await #require(program.rules.first).findings()

    #expect(findings.checks.isEmpty)
    #expect(findings.warnings.count == 1)
    #expect(findings.warnings.first?.location == program.rules.first?.location)
  }
}
