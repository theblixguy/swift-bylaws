import BylawsCore
import BylawsInterpreter
import BylawsPaths
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable dependency checks")
struct DependencyRuleTests {
  @Test("Cycle groups use ordinary Swift arrays", arguments: [
    "[.init(\"Components\", files: [\"Sources/Components/**\"])]",
    "saved",
    "saved + []",
    "[] + saved",
    "[group(\"Components\")]",
    "[shadowedGroup()]",
    "[.init(\"Components\", files: [\"Sources/Components/**\"])] + []",
    "[\"Components\"].map { DependencyGroup($0, files: [\"Sources/Components/**\"]) }",
  ])
  func groupArrays(_ expression: String) async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws
      import BylawsIndex
      let app = Codebase(root: .automatic(), including: ["Sources/**"])
      let saved: [DependencyGroup] = [.init("Components", files: ["Sources/Components/**"])]
      func group(_ name: String) -> DependencyGroup {
        .init(name, files: ["Sources/Components/**"])
      }
      func shadowedGroup() -> DependencyGroup {
        let DependencyGroup = "Components"
        return .init(DependencyGroup, files: ["Sources/Components/**"])
      }
      let rules: [Rule] = [
        Rule("cycles") {
          try await app.checkDependencyCycles(
            between: \(expression),
            modules: ["App"], unitOutputFiles: ["/build/App.o"]
          )
        }
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
    #expect(findings.violations.checkedCount == 3)
  }

  @Test("Folder discovery runs without an index provider")
  func discovery() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws
      let app = Codebase(root: .automatic(), including: ["Sources/**"])
      let rules: [Rule] = [
        Rule("groups") {
          let groups = try await app.dependencyGroups(inFoldersMatching: "Sources/*")
          let names = groups.map { $0.name }
          let paths = groups.flatMap { $0.files }
          return Violations<Offender>(
            rule: "select folder groups", offenders: [], checkedCount: names.count + paths.count
          )
        }
      ]
      """,
      "Sources/Orders/Order.swift": "struct Order {}",
    ])
    let program = await RuleProgram.loaded(
      fromFiles: [
        LexicalFilePath("\(project.rootURL.path)/ProjectRules.swift"),
      ],
      parseCachePolicy: .disabled
    )

    try program.requireNoDiagnostics()
    let findings = try await #require(program.rules.first).findings()
    #expect(findings.violations.checkedCount == 2)
  }

  @Test("Dependency checks pass file patterns and index options", arguments: [
    ("", nil as String?),
    ("allowingWithinFoldersMatching: nil,", nil as String?),
    (
      "allowingWithinFoldersMatching: \"Sources/Components/*\",",
      "Sources/Components/*"
    ),
  ])
  func dependencies(
    folderArgument: String,
    expectedFolderPattern: String?
  ) async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws
      import BylawsIndex
      let app = Codebase(root: .automatic(), including: ["Sources/**"])
      let rules: [Rule] = [
        Rule("references", "Components use permitted files") {
          try await app.checkDependencies(
            from: ["Sources/Components/**"],
            allowingReferencesTo: ["Sources/Contracts/**", "Sources/Common/**"],
            \(folderArgument)
            modules: ["App"],
            unitOutputFiles: ["/build/App.o"]
          )
        },
        Rule("cycles", "Components have no dependency cycles") {
          try await app.checkDependencyCycles(
            between: [.init("Components", files: ["Sources/Components/**"])],
            modules: ["App"],
            unitOutputFiles: ["/build/App.o"]
          )
        }
      ]
      """,
      "Sources/App.swift": "struct App {}",
    ])
    let program = await RuleProgram.loaded(
      fromFiles: [
        LexicalFilePath("\(project.rootURL.path)/ProjectRules.swift"),
      ],
      parseCachePolicy: .disabled,
      indexProvider: RuntimeIndexProviderMock(
        expectedFolderPattern: expectedFolderPattern
      )
    )

    try program.requireNoDiagnostics()
    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.isEmpty)
    #expect(findings.violations.checkedCount == 2)
    let cycleFindings = try await #require(program.rules.last).findings()
    #expect(cycleFindings.violations.checkedCount == 3)
  }
}
