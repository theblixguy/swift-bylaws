import BylawsCore
import BylawsInterpreter
import BylawsPaths
import BylawsTestSupport
import Foundation
import Testing

@Suite("Dependency group compilation")
struct DependencyGroupCompilationTests {
  @Test("Group expressions must have supported types", arguments: [
    "let groups = .init(\"Orders\", files: [\"Sources/**\"])",
    "let groups = DependencyGroup(files: [\"Sources/**\"])",
    "let groups = DependencyGroup(1, files: [\"Sources/**\"])",
    "let groups = DependencyGroup<Int>(\"Orders\", files: [])",
    "let groups = DependencyGroup(\"Orders\", files: \"Sources/**\")",
    "let groups: [DependencyGroup] = [1] + []",
    "let groups = [DependencyGroup(\"Orders\", files: [])] + [1]",
  ])
  func unsupportedExpression(_ declaration: String) async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws
      let app = Codebase(root: .automatic(), including: ["Sources/**"])
      let rules: [Rule] = [
        Rule("groups") {
          \(declaration)
          return try await app.classes.violations(of: .isFinal)
        }
      ]
      """,
      "Sources/App.swift": "final class App {}",
    ])

    let program = await RuleProgram.loaded(
      fromFiles: [
        LexicalFilePath("\(project.rootURL.path)/ProjectRules.swift"),
      ],
      parseCachePolicy: .disabled
    )

    #expect(!program.diagnostics.isEmpty)
    #expect(program.rules.isEmpty)
  }
}
