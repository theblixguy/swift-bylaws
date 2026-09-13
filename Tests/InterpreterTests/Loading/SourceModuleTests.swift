import BylawsCore
import BylawsInterpreter
import BylawsPaths
import BylawsTestSupport
import Foundation
import PortableRules
import Testing

@Suite("Interpreted source modules")
struct SourceModuleTests {
  @Test("A multi-file module returns the same rules as compiled Swift")
  func compiledAndInterpretedModule() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "Bylaws.swift": """
      import Bylaws
      import PortableRules

      nonisolated let app = Codebase(
        root: .automatic(),
        including: ["Sources/**"]
      )
      nonisolated let rules = portableModuleRules(for: app)
      """,
      "Sources/App/Types.swift": """
      class Small { func one() {} }
      class Large { func one() {}; func two() {} }
      """,
    ])
    let index = try PackageModuleIndex(modules: testModules)

    let program = await RuleProgram.loaded(
      fromFiles: [LexicalFilePath("\(project.rootURL.path)/Bylaws.swift")],
      parseCachePolicy: .disabled,
      packageModuleIndex: index
    )
    let interpretedRule = try #require(program.rules.first)
    let compiledRule = try #require(
      portableModuleRules(
        for: Codebase(
          root: .directory(project.rootURL.path),
          including: ["Sources/**"]
        )
      ).first
    )
    let interpreted = try await interpretedRule.findings()
    let compiled = try await compiledRule.findings()

    #expect(program.diagnostics.isEmpty)
    #expect(program.rules.map(\.id) == ["portable-module"])
    #expect(interpreted.violations.offenders.map(\.name) == ["Large"])
    #expect(interpreted.violations.checkedCount == 2)
    #expect(interpreted.violations == compiled.violations)
  }

  @Test("An import needs package graph data")
  func importWithoutPackageGraph() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      import Bylaws
      import PortableRules
      """,
    ])

    let program = await RuleProgram.loaded(
      fromFiles: ["\(project.rootURL.path)/Bylaws.swift"]
    )

    #expect(program.rules.isEmpty)
    #expect(
      program.errors.map(\.message) == [
        "the imported module 'PortableRules' is not available",
      ]
    )
  }

  @Test("An imported module exposes only public declarations")
  func internalDeclaration() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "Bylaws.swift": """
      import Bylaws
      import PortableRules

      nonisolated let app = Codebase(
        root: .directory("."),
        including: ["Sources/**"]
      )
      nonisolated let matcher = Matcher<Class>("stay small") {
        internalHasAtMostOneFunction($0)
      }
      nonisolated let rules: [Rule] = [
        Rule("internal-helper") {
          try await app.classes.violations(of: matcher)
        },
      ]
      """,
      "Sources/App/A.swift": "class A {}",
    ])
    let index = try PackageModuleIndex(modules: testModules)

    let program = await RuleProgram.loaded(
      fromFiles: [LexicalFilePath("\(project.rootURL.path)/Bylaws.swift")],
      parseCachePolicy: .disabled,
      packageModuleIndex: index
    )

    #expect(program.rules.isEmpty)
    #expect(
      program.errors.map(\.message).contains(
        "'internalHasAtMostOneFunction' is not declared"
      )
    )
  }

  @Test("An imported module exposes a public rule binding")
  func publicRuleBinding() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      import Bylaws
      import PortableRules

      nonisolated let rules: [Rule] = portableBindingRules
      """,
    ])
    let index = try PackageModuleIndex(modules: testModules)

    let program = await RuleProgram.loaded(
      fromFiles: [LexicalFilePath("\(project.rootURL.path)/Bylaws.swift")],
      parseCachePolicy: .disabled,
      packageModuleIndex: index
    )
    let rule = try #require(program.rules.first)
    let violations = try await rule.violations()

    #expect(program.diagnostics.isEmpty)
    #expect(program.rules.map(\.id) == ["portable-binding"])
    #expect(violations.rule == "match")
    #expect(violations.checkedCount == 0)
    #expect(violations.offenders.isEmpty)
  }

  @Test("A module import needs a target dependency")
  func moduleDependency() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      import Bylaws
      import PortableRules
      """,
    ])
    var modules = testModules
    modules[0] = PackageModuleIndex.Module(
      name: modules[0].name,
      sourceFiles: modules[0].sourceFiles,
      dependencies: ["Bylaws"]
    )

    let program = await RuleProgram.loaded(
      fromFiles: [LexicalFilePath("\(project.rootURL.path)/Bylaws.swift")],
      parseCachePolicy: .disabled,
      packageModuleIndex: try PackageModuleIndex(modules: modules)
    )

    #expect(
      program.errors.map(\.message).contains(
        "'PortableRules' has no target dependency on "
          + "'PortableRuleSupport'"
      )
    )
  }

  @Test("A portable API import needs its product dependency")
  func portableAPIDependency() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "import Rules",
      "Modules/Rules.swift": """
      public import Bylaws
      public import BylawsIndex
      """,
    ])
    let module = PackageModuleIndex.Module(
      name: "Rules",
      sourceFiles: ["\(project.rootURL.path)/Modules/Rules.swift"],
      dependencies: ["Bylaws"]
    )

    let program = await RuleProgram.loaded(
      fromFiles: [LexicalFilePath("\(project.rootURL.path)/Bylaws.swift")],
      parseCachePolicy: .disabled,
      packageModuleIndex: try PackageModuleIndex(modules: [module])
    )

    #expect(program.rules.isEmpty)
    #expect(
      program.errors.map(\.message) == [
        "'Rules' has no target dependency on 'BylawsIndex'",
      ]
    )
  }

  @Test("Each rules file evaluates only its imported modules")
  func unrelatedModulesAreNotEvaluated() async throws {
    let project = try TemporaryProject(files: [
      "First.swift": """
      import Bylaws
      import PortableRules

      nonisolated let app = Codebase(
        root: .automatic(),
        including: ["Sources/**"]
      )
      nonisolated let rules = portableModuleRules(for: app)
      """,
      "Second.swift": """
      import Bylaws
      import FailingRules
      """,
      "Sources/App/A.swift": "class A {}",
      "Modules/FailingRules.swift": """
      public import Bylaws

      public nonisolated func recursiveRules() -> [Rule] {
        recursiveRules()
      }

      public nonisolated let failingRules: [Rule] = recursiveRules()
      """,
    ])
    let failing = PackageModuleIndex.Module(
      name: "FailingRules",
      sourceFiles: [
        "\(project.rootURL.path)/Modules/FailingRules.swift",
      ],
      dependencies: ["Bylaws"]
    )

    let program = await RuleProgram.loaded(
      fromFiles: [
        LexicalFilePath("\(project.rootURL.path)/First.swift"),
        LexicalFilePath("\(project.rootURL.path)/Second.swift"),
      ],
      parseCachePolicy: .disabled,
      packageModuleIndex: try PackageModuleIndex(
        modules: testModules + [failing]
      )
    )

    #expect(program.rules.map(\.id) == ["portable-module"])
    #expect(
      program.errors.map(\.message) == [
        "the rule exceeded its call-depth limit",
      ]
    )
  }

  @Test("Cyclic modules are not partially loaded")
  func cyclicModules() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      import Bylaws
      import FirstRules
      """,
      "Modules/FirstRules.swift": "import SecondRules",
      "Modules/SecondRules.swift": "import FirstRules",
    ])
    let modules = [
      PackageModuleIndex.Module(
        name: "FirstRules",
        sourceFiles: ["\(project.rootURL.path)/Modules/FirstRules.swift"],
        dependencies: ["SecondRules"]
      ),
      PackageModuleIndex.Module(
        name: "SecondRules",
        sourceFiles: ["\(project.rootURL.path)/Modules/SecondRules.swift"],
        dependencies: ["FirstRules"]
      ),
    ]

    let program = await RuleProgram.loaded(
      fromFiles: [LexicalFilePath("\(project.rootURL.path)/Bylaws.swift")],
      parseCachePolicy: .disabled,
      packageModuleIndex: try PackageModuleIndex(modules: modules)
    )

    #expect(program.rules.isEmpty)
    #expect(
      program.errors.map(\.message) == [
        "the imported module graph contains a cycle at 'FirstRules'",
      ]
    )
  }

  @Test("Unreadable module source reports a file-read error")
  func unreadableModuleSource() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "import MissingRules",
    ])
    let path = "\(project.rootURL.path)/Modules/MissingRules.swift"
    let module = PackageModuleIndex.Module(
      name: "MissingRules",
      sourceFiles: [path],
      dependencies: ["Bylaws"]
    )

    let program = await RuleProgram.loaded(
      fromFiles: [LexicalFilePath("\(project.rootURL.path)/Bylaws.swift")],
      parseCachePolicy: .disabled,
      packageModuleIndex: try PackageModuleIndex(modules: [module])
    )

    #expect(
      program.errors.map(\.message).contains(
        "cannot read the module source file: "
          + readFailureDescription(at: path)
      )
    )
  }

  private var testModules: [PackageModuleIndex.Module] {
    let testModulesDirectory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("TestModules")
    let module = testModulesDirectory.appendingPathComponent(
      "PortableRules"
    )
    let support = testModulesDirectory.appendingPathComponent(
      "PortableRuleSupport"
    )
    return [
      PackageModuleIndex.Module(
        name: "PortableRules",
        sourceFiles: [
          module.appendingPathComponent("Matchers/Matchers.swift").path,
          module.appendingPathComponent("Rules/Rules.swift").path,
        ],
        dependencies: ["Bylaws", "PortableRuleSupport"]
      ),
      PackageModuleIndex.Module(
        name: "PortableRuleSupport",
        sourceFiles: [
          support.appendingPathComponent("Matchers.swift").path,
        ],
        dependencies: ["Bylaws"]
      ),
    ]
  }
}
