import BylawsCore
import BylawsInterpreter
import BylawsPaths
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable project integrations")
struct RuntimeProjectIntegrationTests {
  @Test("Portable rules can use public index APIs")
  func indexCalls() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws
      import BylawsIndex

      let app = Codebase(root: .automatic(), including: ["Sources/**"])

      func includesDefinition(_ roles: Set<SymbolRole>) -> Bool {
        roles.contains(.definition)
      }

      let projectRules: [Rule] = [
        Rule("index", "Located conformers stay in semantics") {
          let index = try await app.projectIndex(modules: ["BylawsSemantics"])
          let conformers = index.conformers(of: "Located")
          let offenders = conformers.filter {
            let roles: Set<SymbolRole> = $0.roles
            return $0.module != "BylawsSemantics"
              && $0.symbol.kind == .struct
              && includesDefinition(roles)
          }
          return Violations(
            rule: "be declared in BylawsSemantics",
            offenders: offenders,
            checkedCount: conformers.count
          )
        },
      ]
      """,
      "Sources/App/A.swift": "struct A {}",
    ])

    let program = await RuleProgram.loaded(
      fromFiles: [
        LexicalFilePath("\(project.rootURL.path)/ProjectRules.swift"),
      ],
      parseCachePolicy: .disabled,
      indexProvider: RuntimeIndexProviderMock()
    )
    try program.requireNoDiagnostics()
    let violations = try await #require(program.rules.first).violations()

    #expect(violations.checkedCount == 2)
    #expect(violations.offenders.map(\.name) == ["UIConformer"])
    #expect(violations.offenders.first?.location.column == 7)
  }

  @Test(
    "Portable rules can call every index query on a codebase",
    arguments: CodebaseIndexQueryCase.cases
  )
  func codebaseIndexQueries(testCase: CodebaseIndexQueryCase) async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws
      import BylawsIndex

      let app = Codebase(root: .automatic(), including: ["Sources/**"])

      let projectRules: [Rule] = [
        Rule("index", "Index queries stay in semantics") {
          let found = try await app.\(
            testCase.call
          ) "Located", modules: ["BylawsSemantics"])
          let offenders = found.filter { $0.module != "BylawsSemantics" }
          return Violations(
            rule: "be declared in BylawsSemantics",
            offenders: offenders,
            checkedCount: found.count
          )
        },
      ]
      """,
      "Sources/App/A.swift": "struct A {}",
    ])

    let program = await RuleProgram.loaded(
      fromFiles: [
        LexicalFilePath("\(project.rootURL.path)/ProjectRules.swift"),
      ],
      parseCachePolicy: .disabled,
      indexProvider: RuntimeIndexProviderMock(expectedQuery: testCase.query)
    )
    try program.requireNoDiagnostics()
    let violations = try await #require(program.rules.first).violations()

    #expect(violations.checkedCount == 2)
    #expect(violations.offenders.map(\.name) == ["UIConformer"])
  }

  @Test("Portable rules can check layering")
  func layeringCheck() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])
      let layers = Layering(
        Layer("Domain", files: ["Sources/Domain/**"]),
        Layer("UI", files: ["Sources/UI/**"], mayImport: ["Domain"])
      )

      func layerCheck(
        _ codebase: Codebase,
        _ layering: Layering
      ) async throws -> LayeringCheck {
        try await codebase.checkLayering(layering)
      }

      let projectRules: [Rule] = [
        Rule("layers", "The layering holds") {
          try await layerCheck(app, layers)
        },
      ]
      """,
      "Sources/Domain/Domain.swift": "import UI\nstruct Domain {}",
      "Sources/UI/UI.swift": "struct UI {}",
    ])
    let program = try await loadedProgram(in: project)

    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.offenders.map(\.name) == ["UI"])
    #expect(findings.warnings.isEmpty)
  }

  @Test("A helper can accept a package target")
  func helperAcceptsPackageTarget() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": """
      // swift-tools-version: 6.2
      import PackageDescription

      let package = Package(
        name: "Example",
        targets: [.target(name: "App")]
      )
      """,
      "ProjectRules.swift": """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])

      func targetName(_ target: PackageManifest.Target) -> String {
        target.name
      }

      let projectRules: [Rule] = [
        Rule("target-name", "Targets use the expected name") {
          let manifest = try await app.packageManifest
          let targets = manifest.targets.possibleValues
          let offenders = targets.filter {
            targetName($0) != "App"
          }
          return Violations(
            rule: "be named App",
            offenders: offenders,
            checkedCount: targets.count
          )
        },
      ]
      """,
      "Sources/App/App.swift": "struct App {}",
    ])
    let program = try await loadedProgram(in: project)

    let violations = try await #require(program.rules.first).violations()

    #expect(violations.checkedCount == 1)
    #expect(violations.isEmpty)
  }

  @Test("Portable rules can check indexed layering")
  func indexedLayeringCheck() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws
      import BylawsIndex

      let app = Codebase(root: .automatic(), including: ["Sources/**"])
      let layers = Layering(
        Layer("Domain", files: ["Sources/Domain/**"]),
        Layer("UI", files: ["Sources/UI/**"], mayImport: ["Domain"])
      )

      let projectRules: [Rule] = [
        Rule("layers", "The layering holds") {
          let findings = try await app.indexedFindings(
            of: layers,
            modules: ["App"]
          )
          return Violations(
            rule: findings.violations.rule,
            offenders: findings.violations.offenders,
            checkedCount: findings.violations.checkedCount
          )
        },
      ]
      """,
      "Sources/App.swift": "struct App {}",
    ])
    let program = await RuleProgram.loaded(
      fromFiles: [
        LexicalFilePath("\(project.rootURL.path)/ProjectRules.swift"),
      ],
      parseCachePolicy: .disabled,
      indexProvider: RuntimeIndexProviderMock()
    )

    try program.requireNoDiagnostics()
    let findings = try await #require(program.rules.first).findings()
    #expect(findings.violations.offenders.map(\.name) == ["ForbiddenUse"])
  }

  @Test("Portable rules can check package dependencies")
  func packageCheck() async throws {
    let project = try packageDependencyProject(
      rulesFile: "ProjectRules.swift",
      rulesSource: """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])
      let projectRules: [Rule] = [
        Rule("manifest", "Package dependencies match imports") {
          app.checkPackageDependencies()
        },
      ]
      """
    )
    let program = try await loadedProgram(in: project)

    let findings = try await #require(program.rules.first).findings()

    expectPackageDependencyFindings(findings)
  }

  @Test("A helper can return package violations")
  func helperReturningPackageViolations() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": """
      // swift-tools-version: 6.2
      import PackageDescription

      let package = Package(
        name: "Example",
        targets: [
          .target(name: "App"),
          .target(name: "Domain"),
        ]
      )
      """,
      "ProjectRules.swift": """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])

      func packageViolations() async throws -> Violations<Import> {
        try await app.checkPackageDependencies().violations
      }

      let projectRules: [Rule] = [
        Rule("manifest-helper", "Package dependencies match imports") {
          let result = try await packageViolations()
          let domainImports = result.offenders.filter { $0.name == "Domain" }
          return Violations(
            rule: result.rule,
            offenders: domainImports,
            checkedCount: result.checkedCount
          )
        },
      ]
      """,
      "Sources/App/App.swift": "import Domain\nstruct App {}",
      "Sources/Domain/Domain.swift": "struct Domain {}",
    ])
    let names = try await offenderNames(ofFirstRuleIn: project)

    #expect(names == ["Domain"])
  }

  @Test("A portable helper can inspect the import graph")
  func importGraph() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": """
      // swift-tools-version: 6.2
      import PackageDescription

      let package = Package(
        name: "Example",
        targets: [
          .target(name: "App", dependencies: ["Domain"]),
          .target(name: "Domain"),
        ]
      )
      """,
      "ProjectRules.swift": """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])
      let zero: Double = 0
      let values: [Double] = [1]

      func positive(_ value: Double) -> Bool { value > zero }
      func one() -> Double { 1 }
      func numbers() -> [Double] { [1] }

      let projectRules: [Rule] = [
        Rule("graph", "App imports Domain") {
          let graph = try await app.importGraph()
          let valid = graph.targets.contains(where: {
            $0.name == "App"
              && $0.imports.contains("Domain")
              && $0.instability > 0
              && 0 < $0.instability
              && positive(1)
              && one() == 1
              && values.count == numbers().count
          })
          let files = try await app.files
          let matchesGraph = Matcher<SourceFile>("belong to a valid graph") {
            valid
          }
          return files.violations(of: matchesGraph)
        },
      ]
      """,
      "Sources/App/App.swift": "import Domain\nstruct App {}",
      "Sources/Domain/Domain.swift": "struct Domain {}",
    ])
    let program = try await loadedProgram(in: project)

    let violations = try await #require(program.rules.first).violations()

    #expect(violations.isEmpty)
    #expect(violations.checkedCount == 2)
  }
}

struct CodebaseIndexQueryCase: Sendable, CustomTestStringConvertible {
  let call: String
  let query: RuntimeIndexQuery

  var testDescription: String { call }

  static let cases = [
    CodebaseIndexQueryCase(call: "conformers(of:", query: .conformers),
    CodebaseIndexQueryCase(
      call: "directConformers(of:",
      query: .directConformers
    ),
    CodebaseIndexQueryCase(call: "references(to:", query: .references),
    CodebaseIndexQueryCase(call: "definitions(of:", query: .definitions),
    CodebaseIndexQueryCase(call: "occurrences(of:", query: .occurrences),
  ]
}
