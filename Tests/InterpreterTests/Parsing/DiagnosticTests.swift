import BylawsInterpreter
import BylawsTestSupport
import Foundation
import Testing

@Suite("Rules-file diagnostics")
struct DiagnosticTests {
  @Test("A rules file that does not parse loads no rules")
  func syntaxErrorDiagnoses() async throws {
    let (program, _) = try await diagnostics(forRules: """
    let app = Codebase(including: ["Sources/**"])

    Rule("no-print", "Files stay free of print") {
      app.calls.violations(matching: .references("print")
    }
    """)

    #expect(program.rules.isEmpty)
    #expect(!program.errors.isEmpty)
  }

  @Test("An operator outside the subset produces a diagnostic")
  func unknownOperatorDiagnoses() async throws {
    let (program, _) = try await diagnostics(forRules: """
    let app = Codebase(including: ["Sources/**"])

    Rule("final-classes", "Classes are final") {
      app.classes.violations(of: .isFinal ~> .isPublic)
    }
    """)

    #expect(program.rules.isEmpty)
    #expect(!program.errors.isEmpty)
  }

  @Test("A malformed layer argument produces a diagnostic")
  func malformedLayerArgumentDiagnoses() async throws {
    let (program, _) = try await diagnostics(forRules: """
    let app = Codebase(including: ["Sources/**"])

    let layering = Layering(
      Layer("Domain", files: ["Sources/Domain/**"]),
      Layer("UI", files: ["Sources/UI/**"], mayImport: 42)
    )

    Rule("layering", "The declared layering holds") {
      app.checkLayering(layering)
    }
    """)

    let diagnostic = try #require(program.errors.first)
    #expect(
      diagnostic.message
        == "'mayImport' takes an array of layer names or '.any'"
    )
  }

  @Test("Two sibling modules cannot declare one rule id")
  func siblingIDCollisionDiagnoses() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["**"])

      Rule("root-docs", "Public classes carry documentation") {
        app.classes.violations(of: .hasDocumentation)
      }
      """,
      "Modules/A/Package.swift": "// swift-tools-version: 6.0",
      "Modules/A/Bylaws.swift": """
      let a = Codebase(including: ["Sources/**"])

      Rule("no-print", "Files stay free of print") {
        a.calls.violations(matching: .references("print"))
      }
      """,
      "Modules/B/Package.swift": "// swift-tools-version: 6.0",
      "Modules/B/Bylaws.swift": """
      let b = Codebase(including: ["Sources/**"])

      Rule("no-print", "Files stay free of print") {
        b.calls.violations(matching: .references("print"))
      }
      """,
      "Modules/A/Sources/A.swift": "class A {}",
      "Modules/B/Sources/B.swift": "class B {}",
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)
    let diagnostic = try #require(program.errors.first)
    #expect(diagnostic.message == "'no-print' is declared twice")
  }

  @Test(
    "Each structurally invalid declaration produces a diagnostic",
    arguments: StructuralDiagnosticCase.cases
  )
  func structurallyInvalidDeclarationDiagnoses(
    _ testCase: StructuralDiagnosticCase
  ) async throws {
    let (program, _) = try await diagnostics(forRules: testCase.source)
    #expect(program.errors.map(\.message).contains(testCase.message))
  }
}

struct StructuralDiagnosticCase: Sendable, CustomTestStringConvertible {
  let source: String
  let message: String

  var testDescription: String { message }

  static let cases = [
    StructuralDiagnosticCase(
      source:
      """
      var app = Codebase(including: ["Sources/**"])
      Rule("r", "Rule") { app.classes.violations(of: .isFinal) }
      """,
      message: "a binding here must start with 'let name = Codebase(' or "
        + "'let name = Layering('"
    ),
    StructuralDiagnosticCase(
      source:
      """
      let app = Codebase(including: ["Sources/**"])
      let app = Codebase(including: ["Tests/**"])
      Rule("r", "Rule") { app.classes.violations(of: .isFinal) }
      """,
      message: "'app' is declared twice"
    ),
    StructuralDiagnosticCase(
      source:
      """
      let app = Codebase(
        including: ["Sources/**"],
        including: ["Tests/**"]
      )
      Rule("r", "Rule") { app.classes.violations(of: .isFinal) }
      """,
      message: "'including' appears more than once"
    ),
    StructuralDiagnosticCase(
      source:
      """
      let app = Codebase(including: ["Sources/**"])
      let layers = Layering(Layer("Domain", "Data", files: ["Sources/**"]))
      Rule("r", "Rule") { app.checkLayering(layers) }
      """,
      message: "Layer takes one unlabelled name"
    ),
    StructuralDiagnosticCase(
      source:
      """
      let app = Codebase(including: ["Sources/**"])
      let layers = Layering(Layer(files: ["Sources/**"], "Domain"))
      Rule("r", "Rule") { app.checkLayering(layers) }
      """,
      message: "Layer takes one unlabelled name"
    ),
    StructuralDiagnosticCase(
      source:
      """
      let app = Codebase(including: ["Sources/**"])
      Rule("r", enforcement: .advisory, "Rule") {
        app.classes.violations(of: .isFinal)
      }
      """,
      message: "Rule takes plain string literals here"
    ),
    StructuralDiagnosticCase(
      source:
      """
      let app = Codebase(including: ["Sources/**"])
      Rule(
        "r",
        "Rule",
        enforcement: .advisory,
        enforcement: .enforced
      ) { app.classes.violations(of: .isFinal) }
      """,
      message: "'enforcement' appears more than once"
    ),
    StructuralDiagnosticCase(
      source:
      """
      let app = Codebase(including: ["Sources/**"])
      Rule("r", "Rule") {
        app.classes.violations(of: .isFinal)
      } alternative: {
        app.classes.violations(of: .isPublic)
      }
      """,
      message: "Rule takes one trailing body closure"
    ),
    StructuralDiagnosticCase(
      source:
      """
      let app = Codebase(including: ["Sources/**"])
      Rule("r", "Rule") {
        app.classes.violations(of: .isFinal) { arbitraryWork() }
      }
      """,
      message: "'violations' takes no trailing closure"
    ),
    StructuralDiagnosticCase(
      source:
      """
      let app = Codebase(including: ["Sources/**"])
      Rule("r", "Rule") {
        app.classes.violations(of: .isFinal { arbitraryWork() })
      }
      """,
      message: "'isFinal' takes no trailing closure"
    ),
    StructuralDiagnosticCase(
      source:
      """
      let app = Codebase(including: ["Sources/**"])
      Rule("r", "Rule") { ignored in
        app.classes.violations(of: .isFinal)
      }
      """,
      message: "a rule's body must be one query expression"
    ),
  ]
}
