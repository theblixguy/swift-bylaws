import BylawsInterpreter
import Foundation
import Testing

@Suite("Bylaws process")
struct CLIProcessTests {
  @Test("Passing rules exit with code 0 and write only standard output")
  func cleanRun() throws {
    let project = try CLIProcessProject(
      source: "final class Good {}",
      rules: CLIProcessMock.finalClassesRule
    )

    let result = try project.run()

    #expect(result.status == 0)
    #expect(
      result.standardOutput
        .contains("Checked 1 rule: 0 violations.")
    )
    #expect(result.standardError.isEmpty)
  }

  @Test("Enforced violation exits with code 1")
  func enforcedViolation() throws {
    let project = try CLIProcessProject(
      source: "class Bad {}",
      rules: CLIProcessMock.finalClassesRule
    )

    let result = try project.run()

    #expect(result.status == 1)
    #expect(result.standardOutput.contains("Bad violates 'Classes are final'"))
    #expect(result.standardError.isEmpty)
  }

  @Test("Closure rule reports class that exceeds function limit")
  func portableClosureRule() throws {
    let project = try CLIProcessProject(
      source: """
      class Small { func one() {} }
      class Large { func one() {}; func two() {} }
      """,
      rules: """
      import Bylaws
      import Testing

      let app = Codebase(root: .automatic(), including: ["Sources/**"])

      func hasAtMostOneFunction(_ declaration: Class) -> Bool {
        declaration.functions.count <= 1
      }

      let isSmall = Matcher<Class>("declare at most one function") {
        hasAtMostOneFunction($0)
      }

      let projectRules: [Rule] = [
        Rule("class-size", "Classes stay small") {
          try await app.classes.violations(of: isSmall)
        },
      ]
      """
    )

    let result = try project.run()

    #expect(result.status == 1)
    #expect(result.standardOutput
      .contains("Large violates 'Classes stay small'"))
    #expect(result.standardError.isEmpty)
  }

  @Test("CLI commands load rules from a SwiftPM source module")
  func sourceModuleCommands() throws {
    let project = try CLIProcessProject(
      source: "class Small { func one() {} }\nclass Large { func one() {}; func two() {} }",
      rules: """
      import Bylaws
      import CompanyRules

      nonisolated let app = Codebase(
        root: .automatic(),
        including: ["Sources/**"]
      )
      nonisolated let rules = companyRules(for: app)
      """,
      extraFiles: [
        "CompanyRules/Matchers.swift": """
        import Bylaws

        nonisolated func isSmall(_ declaration: Class) -> Bool {
          declaration.functions.count <= 1
        }
        """,
        "CompanyRules/Rules.swift": """
        public import Bylaws

        public nonisolated func companyRules(
          for codebase: Codebase
        ) -> [Rule] {
          let matcher = Matcher<Class>("stay small") { isSmall($0) }
          return [
            Rule("company-rule", "Classes stay small") {
              try await codebase.classes.violations(of: matcher)
            },
          ]
        }
        """,
      ]
    )
    let index = try PackageModuleIndex(modules: [
      PackageModuleIndex.Module(
        name: "CompanyRules",
        sourceFiles: [
          project.root.appendingPathComponent("CompanyRules/Matchers.swift")
            .path,
          project.root.appendingPathComponent("CompanyRules/Rules.swift").path,
        ],
        dependencies: ["Bylaws"]
      ),
    ])
    let indexURL = project.root.appendingPathComponent("modules.json")
    try JSONEncoder().encode(index).write(to: indexURL)

    let result = try project.run(
      "--swift-package-modules",
      indexURL.path
    )

    #expect(result.status == 1)
    #expect(result.standardOutput
      .contains("Large violates 'Classes stay small'"))
    #expect(result.standardError.isEmpty)

    let listing = try project.runRules(
      "--swift-package-modules",
      indexURL.path
    )
    #expect(listing.status == 0)
    #expect(listing.standardOutput.contains("company-rule"))
    #expect(listing.standardError.isEmpty)
  }

  @Test("Module index with non-Swift source path reports path and cause")
  func nonSwiftModulePath() throws {
    let project = try CLIProcessProject(
      source: "final class Good {}",
      rules: CLIProcessMock.finalClassesRule,
      extraFiles: [
        "modules.json": """
        {
          "modules": [{
            "name": "CompanyRules",
            "sourceFiles": ["CompanyRules/Rules.txt"],
            "dependencies": ["Bylaws"]
          }]
        }
        """,
      ]
    )

    let result = try project.run(
      "--swift-package-modules",
      "modules.json"
    )

    #expect(result.status == 2)
    #expect(
      result.standardOutput.contains(
        "cannot read the SwiftPM module index at 'modules.json': "
          + "module 'CompanyRules' has an empty or non-Swift source path: "
          + "'CompanyRules/Rules.txt'"
      )
    )
    #expect(result.standardError.isEmpty)
  }

  @Test("Rule syntax error exits with code 2")
  func ruleSyntaxError() throws {
    let project = try CLIProcessProject(
      source: "class Bad {}",
      rules: "let app = Codebase("
    )

    let result = try project.run()

    #expect(result.status == 2)
    #expect(result.standardOutput.contains("error:"))
    #expect(result.standardError.isEmpty)
  }

  @Test("Missing rules file exits with code 2")
  func missingRulesFile() throws {
    let project = try CLIProcessProject(source: "class App {}", rules: nil)

    let result = try project.run()

    #expect(result.status == 2)
    #expect(result.standardOutput.contains("no Bylaws.swift found"))
    #expect(result.standardError.isEmpty)
  }

  @Test("Missing project marker exits with code 2")
  func unresolvedProjectRoot() throws {
    let project = try CLIProcessProject(
      source: "class App {}",
      rules: nil,
      writesProjectMarker: false
    )

    let result = try project.runResolvingRoot()

    #expect(result.status == 2)
    #expect(result.standardOutput
      .contains("Bylaws cannot find a Swift package"))
    #expect(!result.standardOutput.contains("Usage:"))
    #expect(result.standardError.isEmpty)
  }

  @Test("Rules command reports error for path outside project")
  func rulesPathOutsideProject() throws {
    let project = try CLIProcessProject(
      source: "final class App {}",
      rules: CLIProcessMock.finalClassesRule
    )

    let result = try project.runRules("--for", "/outside/App.swift")

    #expect(result.status == 2)
    #expect(result.standardOutput.contains("error:"))
    #expect(result.standardOutput.contains("is outside"))
    #expect(!result.standardOutput.contains("Usage:"))
    #expect(result.standardError.isEmpty)
  }

  @Test("Advisory violation exits with code 1 in strict mode")
  func strictAdvisory() throws {
    let project = try CLIProcessProject(
      source: "class Bad {}",
      rules: CLIProcessMock.finalClassesRule.replacing(
        "Rule(\"final-classes\", \"Classes are final\")",
        with: "Rule(\"final-classes\", \"Classes are final\", enforcement: .advisory)"
      )
    )

    #expect(try project.run().status == 0)
    #expect(try project.run("--strict").status == 1)
  }

  @Test("Rule selection runs only requested ID")
  func ruleSelection() throws {
    let project = try CLIProcessProject(
      source: "class Bad {}\nfinal class Good {}",
      rules: """
      let app = Codebase(including: ["Sources/**"])

      Rule("failing", "Classes are final") {
        app.classes.violations(of: .isFinal)
      }

      Rule("passing", "Good is final") {
        app.classes.named("Good").violations(of: .isFinal)
      }
      """
    )

    let result = try project.run("--only", "passing")

    #expect(result.status == 0)
    #expect(
      result.standardOutput
        .contains("Checked 1 rule: 0 violations.")
    )
  }
}
