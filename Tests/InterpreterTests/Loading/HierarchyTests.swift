import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Rules-file hierarchy")
struct HierarchyTests {
  @Test("A layering override excludes its subtree from the root rule")
  func layeringOverrideExcludesScope() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**", "Modules/**"])

      let layering = Layering(
        Layer("Domain", files: ["Sources/Domain/**", "Modules/Feature/Sources/Domain/**"]),
        Layer("UI", files: ["Sources/UI/**"], mayImport: ["Domain"])
      )

      Rule("layers", "The declared layering holds") {
        app.checkLayering(layering)
      }
      """,
      "Modules/Feature/Package.swift": "// swift-tools-version: 6.0",
      "Modules/Feature/Bylaws.swift": """
      let feature = Codebase(including: ["Sources/**"])

      Override("layers", reason: "feature migrates later") {
        feature.files.violations(matching: .imports("Nonexistent"))
      }
      """,
      "Sources/Domain/User.swift": "import UI\nstruct User {}",
      "Sources/UI/Home.swift": "struct Home {}",
      "Modules/Feature/Sources/Domain/Order.swift": "import UI\nstruct Order {}",
    ])

    let program = try await discoveredProgram(in: project)
    let root = try #require(
      program.rules.first {
        $0.id == "layers" && !$0.location.filePath.contains("Modules/")
      }
    )

    let violations = try await root.violations()
    #expect(violations.count == 1)
    let offender = try #require(violations.offenders.first)
    #expect(offender.location.filePath.hasSuffix("Sources/Domain/User.swift"))
    #expect(!offender.location.filePath.contains("Modules/"))
  }

  @Test("A module override excludes its subtree from the root rule")
  func overrideExcludesScope() async throws {
    let project = try Self.makeProject()
    let program = try await discoveredProgram(in: project)
    #expect(program.rules.count == 3)

    let root = try #require(
      program.rules
        .first {
          $0.id == "viewmodel-inheritance" && !$0.location.filePath
            .contains("Billing")
        }
    )
    let rootViolations = try await root.violations()
    #expect(rootViolations.count == 1)
    #expect(
      try #require(rootViolations.offenders.first)
        .description.contains("HomeViewModel")
    )

    let override = try #require(
      program.rules
        .first {
          $0.location.filePath.contains("Billing") && $0
            .id == "viewmodel-inheritance"
        }
    )
    #expect(override.name == "ViewModels inherit from BaseViewModel")
    let overrideViolations = try await override.violations()
    #expect(overrideViolations.isEmpty)
  }

  @Test("A nested override excludes its subtree from its parent override")
  func nestedOverrideExcludesParentScope() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**", "Modules/**"])
      Rule("r", "Classes follow the rule for their module") {
        app.classes.violations(of: .isFinal)
      }
      """,
      "Sources/Root.swift": "class Root {}",
      "Modules/A/Package.swift": "// swift-tools-version: 6.0",
      "Modules/A/Bylaws.swift": """
      let a = Codebase(including: ["Sources/**", "Sub/**"])
      Override("r", reason: "A uses its own rule") {
        a.classes.violations(of: .isFinal)
      }
      """,
      "Modules/A/Sources/A.swift": "class A {}",
      "Modules/A/Sub/Package.swift": "// swift-tools-version: 6.0",
      "Modules/A/Sub/Bylaws.swift": """
      let sub = Codebase(including: ["Sources/**"])
      Override("r", reason: "Sub uses its own rule") {
        sub.classes.violations(of: .isPublic)
      }
      """,
      "Modules/A/Sub/Sources/Sub.swift": "class Sub {}",
    ])

    let program = try await discoveredProgram(in: project)
    #expect(program.rules.count == 3)

    let rootRules = program.rules(applyingTo: "Sources/Root.swift")
    #expect(rootRules.count == 1)
    #expect(rootRules.map(\.location.filePath).allSatisfy {
      !$0.contains("Modules/")
    })

    let moduleRules = program.rules(applyingTo: "Modules/A/Sources/A.swift")
    #expect(moduleRules.count == 1)
    #expect(moduleRules.map(\.location.filePath).allSatisfy {
      $0.hasSuffix("Modules/A/Bylaws.swift")
    })

    let nestedRules = program.rules(
      applyingTo: "Modules/A/Sub/Sources/Sub.swift"
    )
    #expect(nestedRules.count == 1)
    #expect(nestedRules.map(\.location.filePath).allSatisfy {
      $0.hasSuffix("Modules/A/Sub/Bylaws.swift")
    })

    var violations: [Violations<Offender>] = []
    for rule in program.rules {
      violations.append(try await rule.violations())
    }
    #expect(violations.map(\.count) == [1, 1, 1])
    #expect(violations.map { $0.offenders.map(\.name) } == [
      ["Root"], ["A"], ["Sub"],
    ])
  }

  @Test("A module adds its own rule for its subtree")
  func moduleAddsRule() async throws {
    let project = try Self.makeProject()
    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)

    let added = try #require(program.rules.first { $0.id == "billing-docs" })
    let violations = try await added.violations()
    #expect(violations.count == 1)
    #expect(
      try #require(violations.offenders.first)
        .location.filePath.contains("Billing")
    )
  }

  @Test(
    "An invalid module declaration produces a diagnostic",
    arguments: ModuleDiagnosticCase.cases
  )
  func wrongModuleDeclarationDiagnoses(_ testCase: ModuleDiagnosticCase)
    async throws
  {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": finalClassRuleSource,
      "Modules/A/Package.swift": "// swift-tools-version: 6.0",
      "Modules/A/Bylaws.swift": """
      let a = Codebase(including: ["**"])
      \(testCase.rules)
      """,
      "Modules/A/Sources/A.swift": "class A {}",
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)
    let diagnostic = try #require(program.errors.first)
    try expectDiagnostic(
      diagnostic,
      messageContaining: testCase.message,
      hintContaining: testCase.hint
    )
  }

  @Test("Two overrides in one module produce a diagnostic")
  func duplicateOverrideDiagnoses() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": finalClassRuleSource,
      "Modules/A/Package.swift": "// swift-tools-version: 6.0",
      "Modules/A/Bylaws.swift": """
      let a = Codebase(including: ["**"])
      Override("r", reason: "first") {
        a.classes.violations(of: .isFinal)
      }
      Override("r", reason: "second") {
        a.classes.violations(of: .isPublic)
      }
      """,
      "Modules/A/Sources/A.swift": "class A {}",
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)
    let diagnostic = try #require(program.errors.first)
    #expect(diagnostic.message == "'r' is declared twice")
  }

  @Test("Sibling modules can override the same rule")
  func siblingOverridesLoad() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": finalClassRuleSource,
      "Modules/A/Package.swift": "// swift-tools-version: 6.0",
      "Modules/A/Bylaws.swift": """
      let a = Codebase(including: ["**"])
      Override("r", reason: "A") {
        a.classes.violations(of: .isPublic)
      }
      """,
      "Modules/B/Package.swift": "// swift-tools-version: 6.0",
      "Modules/B/Bylaws.swift": """
      let b = Codebase(including: ["**"])
      Override("r", reason: "B") {
        b.classes.violations(of: .hasDocumentation)
      }
      """,
      "Modules/A/Sources/A.swift": "class A {}",
      "Modules/B/Sources/B.swift": "class B {}",
    ])

    let program = try await discoveredProgram(in: project)
    #expect(program.rules.count == 3)
    #expect(program.rules(applyingTo: "Modules/A/Sources/A.swift").count == 1)
    #expect(program.rules(applyingTo: "Modules/B/Sources/B.swift").count == 1)
  }

  private static func makeProject() throws -> TemporaryProject {
    try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["**"])

      Rule("viewmodel-inheritance", "ViewModels inherit from BaseViewModel") {
        app.classes.suffixed("ViewModel").violations(of: .inherits(from: "BaseViewModel"))
      }
      """,
      "Sources/App/Home.swift": "class HomeViewModel {}",
      "Modules/Billing/Package.swift": "// swift-tools-version: 6.0",
      "Modules/Billing/Bylaws.swift": """
      let billing = Codebase(including: ["Sources/**"])

      Override("viewmodel-inheritance", reason: "billing migrates later, JIRA-1") {
        billing.classes.suffixed("ViewModel").violations(of: .inherits(from: "LegacyViewModel"))
      }

      Rule("billing-docs", "Billing types carry documentation") {
        billing.classes.violations(of: .hasDocumentation)
      }
      """,
      "Modules/Billing/Sources/Invoice.swift": """
      class InvoiceViewModel: LegacyViewModel {}
      """,
    ])
  }

  struct ModuleDiagnosticCase: Sendable, CustomTestStringConvertible {
    let rules: String
    let message: String
    let hint: String?

    var testDescription: String { message }

    static let cases = [
      ModuleDiagnosticCase(
        rules: "Rule(\"r\", \"Rule\") { a.classes.violations(of: .isFinal) }",
        message: "duplicate root rule ID",
        hint: "Override"
      ),
      ModuleDiagnosticCase(
        rules: """
        Override("missing", reason: "nothing to replace") {
          a.classes.violations(of: .isFinal)
        }
        """,
        message: "not a rule the root file declares",
        hint: nil
      ),
      ModuleDiagnosticCase(
        rules: "Override(\"r\") { a.classes.violations(of: .isFinal) }",
        message: "Override takes a reason",
        hint: nil
      ),
    ]
  }
}
