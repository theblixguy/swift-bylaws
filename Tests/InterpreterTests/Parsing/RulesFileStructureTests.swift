import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Rules-file structure")
struct RulesFileStructureTests {
  @Test(
    "Parsing continues after an invalid top-level item",
    arguments: RecoveryCase.cases
  )
  func continuesAfterInvalidItem(_ testCase: RecoveryCase) async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      \(testCase.invalidSource)
      Rule("valid", "Valid") { app.classes.violations(of: .isFinal) }
      """,
      "Sources/App/A.swift": "final class A {}",
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)
    #expect(program.errors.count == 1)
    let diagnostic = try #require(
      program.errors.first { $0.message == testCase.message }
    )
    #expect(diagnostic.location.filePath.hasSuffix("/Bylaws.swift"))
    #expect(diagnostic.location.line == 2)
    #expect(program.rules.map(\.id.rawValue) == ["valid"])
  }

  struct RecoveryCase: Sendable {
    let invalidSource: String
    let message: String

    static let cases = [
      RecoveryCase(
        invalidSource: "struct Helper {}",
        message: "portable rules do not support this top-level code"
      ),
      RecoveryCase(
        invalidSource: "import Dispatch",
        message: "the imported module 'Dispatch' is not available"
      ),
      RecoveryCase(
        invalidSource: "var other = Codebase(including: [\"Sources/**\"])",
        message: "a binding here must start with 'let name = Codebase(' or "
          + "'let name = Layering('"
      ),
      RecoveryCase(
        invalidSource: "Rule(\"broken\", \"Broken\")",
        message: "a rule's body must be one query expression"
      ),
    ]
  }
}
