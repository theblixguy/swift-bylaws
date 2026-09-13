import BylawsCore
import BylawsPaths
import BylawsRunner
import BylawsTestSupport
import Foundation
import Testing

@Suite("Rule source parse failures")
struct RuleParseFailureTests {
  @Test("Rule failures include source paths for parse errors", arguments: [
    """
    Rule("classes") { app.classes.violations(of: .isFinal) }
    """,
    """
    Rule("layers") { app.checkLayering(layers) }
    """,
    """
    func checkClasses(_ codebase: Codebase) async -> Violations<Class> {
      try await codebase.classes.violations(of: .isFinal)
    }
    let rules: [Rule] = [Rule("classes") { try await checkClasses(app) }]
    """,
    """
    func checkLayers(_ codebase: Codebase) async -> LayeringCheck {
      try await codebase.checkLayering(layers)
    }
    let rules: [Rule] = [Rule("layers") { try await checkLayers(app) }]
    """,
    """
    let violations = try await app.classes.violations(of: .isFinal)
    let rules: [Rule] = [Rule("classes") { violations }]
    """,
  ])
  func sourceFailure(rule: String) async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "Bylaws.swift": """
      import Bylaws
      let app = Codebase(including: ["Sources/**"])
      let layers = Layering(Layer("App", files: ["Sources/**"]))
      \(rule)
      """,
      "Sources/App/App.swift": "final class App {}",
    ])
    let path = project.fileURL(for: "Sources/App/App.swift").path
    let result = try await RuleRunner.run(RuleRunConfiguration(
      root: LexicalFilePath(project.rootURL.path),
      overlay: SourceOverlay([path: "class App {"])
    ))

    #expect(result.pathsThatDidNotParse == [path])
    #expect(result.diagnostics.count == 1)
  }

  @Test(
    "Other load errors clear source parse failure paths",
    arguments: [
      "let value: String = 1",
      """
      func makeRules() -> [Rule] { makeRules() }
      let rules: [Rule] = makeRules()
      """,
      """
      let empty = Violations<Class>(rule: "match", offenders: [], checkedCount: 0)
      let rules: [Rule] = [Rule("duplicate") { empty }, Rule("duplicate") { empty }]
      """,
    ]
  )
  func otherLoadFailure(otherRules: String) async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "Bylaws.swift": """
      import Bylaws
      let app = Codebase(including: ["Sources/**"])
      let violations = try await app.classes.violations(of: .isFinal)
      let rules: [Rule] = [Rule("classes") { violations }]
      """,
      "Other.swift": "import Bylaws\n\(otherRules)",
      "Sources/App/App.swift": "final class App {}",
    ])
    let result = try await RuleRunner.run(RuleRunConfiguration(
      root: LexicalFilePath(project.rootURL.path),
      ruleFilePaths: [
        LexicalFilePath(project.fileURL(for: "Bylaws.swift").path),
        LexicalFilePath(project.fileURL(for: "Other.swift").path),
      ],
      overlay: SourceOverlay([
        project.fileURL(for: "Sources/App/App.swift").path: "class App {",
      ])
    ))

    #expect(result.pathsThatDidNotParse.isEmpty)
    #expect(result.diagnostics.count >= 2)
  }
}
