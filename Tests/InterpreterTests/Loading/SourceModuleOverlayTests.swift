import BylawsCore
import BylawsInterpreter
import BylawsPaths
import BylawsTestSupport
import Foundation
import Testing

@Suite("Editor text in imported rule modules")
struct SourceModuleOverlayTests {
  @Test("Imported helper returns rules from editor text", arguments: [
    (moduleName: "Rules", functionName: "makeRules"),
    (moduleName: "Support", functionName: "supportRules"),
  ])
  func helperText(moduleName: String, functionName: String) async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "Bylaws.swift": """
      import Rules
      let rules: [Rule] = makeRules()
      """,
      "Modules/Rules.swift": """
      import Bylaws
      import Support
      public func makeRules() -> [Rule] { supportRules() }
      """,
      "Modules/Support.swift": Self.rulesSource(id: "saved"),
    ])
    let modules = [
      PackageModuleIndex.Module(
        name: "Rules",
        sourceFiles: ["\(project.rootURL.path)/Modules/Rules.swift"],
        dependencies: ["Bylaws", "Support"]
      ),
      PackageModuleIndex.Module(
        name: "Support",
        sourceFiles: ["\(project.rootURL.path)/Modules/Support.swift"],
        dependencies: ["Bylaws"]
      ),
    ]
    let source = Self.rulesSource(id: "edited", functionName: functionName)
    let program = await RuleProgram.loaded(
      fromFiles: [LexicalFilePath("\(project.rootURL.path)/Bylaws.swift")],
      parseCachePolicy: .disabled,
      overlay: SourceOverlay(
        ["\(project.rootURL.path)/Modules/\(moduleName).swift": source]
      ),
      packageModuleIndex: try PackageModuleIndex(modules: modules)
    )

    try program.requireNoDiagnostics()
    #expect(program.rules.map(\.id) == ["edited"])
  }

  @Test("Imported codebase reports violations from editor source text")
  func codebaseText() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "Bylaws.swift": """
      import Rules
      let rules: [Rule] = makeRules()
      """,
      "Modules/Rules.swift": """
      import Bylaws
      let app = Codebase(root: .automatic(), including: ["Sources/**"])
      public func makeRules() -> [Rule] {
        [Rule("classes") { try await app.classes.violations(of: .isFinal) }]
      }
      """,
      "Sources/App/App.swift": "final class Saved {}",
    ])
    let program = await RuleProgram.loaded(
      fromFiles: [LexicalFilePath("\(project.rootURL.path)/Bylaws.swift")],
      parseCachePolicy: .disabled,
      overlay: SourceOverlay(
        ["\(project.rootURL.path)/Sources/App/App.swift": "class Edited {}"]
      ),
      packageModuleIndex: try PackageModuleIndex(modules: [
        .init(
          name: "Rules",
          sourceFiles: ["\(project.rootURL.path)/Modules/Rules.swift"],
          dependencies: ["Bylaws"]
        ),
      ])
    )

    try program.requireNoDiagnostics()
    let rule = try #require(program.rules.first)
    #expect(try await rule.violations().offenders.map(\.name) == ["Edited"])
  }

  private static func rulesSource(
    id: String,
    functionName: String = "supportRules"
  ) -> String {
    """
    import Bylaws
    public func \(functionName)() -> [Rule] {
      [Rule("\(id)") {
        Violations<Class>(rule: "match", offenders: [], checkedCount: 0)
      }]
    }
    """
  }
}
