import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Interpreted rule hints")
struct RuleHintTests {
  @Test("A rule includes its declared hint")
  func ruleCarriesItsHint() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])

      Rule(
        "final-screens",
        "Screen classes say final",
        hint: "a subclass of a screen belongs in Sources/Legacy"
      ) {
        app.classes.suffixed("Screen").violations(of: .isFinal)
      }
      """,
      "Sources/App/Home.swift": "class HomeScreen {}",
    ])

    let program = try await discoveredProgram(in: project)

    let rule = try #require(program.rules.first)
    #expect(rule.hint == "a subclass of a screen belongs in Sources/Legacy")
  }

  @Test("A rule without a declared hint has no hint")
  func ruleWithoutHintCarriesNone() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])

      Rule("final-screens", "Screen classes say final") {
        app.classes.suffixed("Screen").violations(of: .isFinal)
      }
      """,
      "Sources/App/Home.swift": "class HomeScreen {}",
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)
    #expect(try #require(program.rules.first).hint == nil)
  }

  @Test(
    "An override inherits or replaces the root hint",
    arguments: OverrideHintCase.cases
  )
  func overrideInheritsOrReplacesTheHint(
    _ testCase: OverrideHintCase
  ) async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["**"])

      Rule(
        "final-screens",
        "Screen classes say final",
        hint: "a screen belongs in Sources/App"
      ) {
        app.classes.suffixed("Screen").violations(of: .isFinal)
      }
      """,
      "Modules/Billing/Package.swift": "// swift-tools-version: 6.0",
      "Modules/Billing/Bylaws.swift": """
      let billing = Codebase(including: ["Sources/**"])

      \(testCase.declaration) {
        billing.classes.suffixed("Screen").violations(of: .isPublic)
      }
      """,
      "Modules/Billing/Sources/Invoice.swift": "class InvoiceScreen {}",
    ])

    let program = try await discoveredProgram(in: project)

    let override = try #require(
      program.rules.first { $0.location.filePath.contains("Billing") }
    )
    #expect(override.hint == testCase.expectedHint)
  }

  @Test("A computed hint produces a diagnostic")
  func computedHintDiagnoses() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])

      Rule(
        "final-screens",
        "Screen classes say final",
        hint: "a screen belongs in " + "Sources/App"
      ) {
        app.classes.suffixed("Screen").violations(of: .isFinal)
      }
      """,
      "Sources/App/Home.swift": "class HomeScreen {}",
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)
    let diagnostic = try #require(program.errors.first)
    #expect(diagnostic.message.contains("'hint:' takes a plain string literal"))
  }
}

struct OverrideHintCase: Codable, Sendable, CustomTestStringConvertible {
  let testDescription: String
  let declaration: String
  let expectedHint: String

  static let cases = [
    OverrideHintCase(
      testDescription: "The override inherits the root hint",
      declaration:
      "Override(\"final-screens\", reason: \"legacy screens, JIRA-1\")",
      expectedHint: "a screen belongs in Sources/App"
    ),
    OverrideHintCase(
      testDescription: "The override replaces the root hint",
      declaration: """
      Override(
        "final-screens",
        reason: "legacy screens, JIRA-1",
        hint: "billing screens move with the migration"
      )
      """,
      expectedHint: "billing screens move with the migration"
    ),
  ]
}
