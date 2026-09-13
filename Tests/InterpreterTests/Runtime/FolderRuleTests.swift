import BylawsCore
import BylawsInterpreter
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable folder rules")
struct FolderRuleTests {
  @Test("Standalone rules check folders and type paths")
  func standaloneRules() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("folders", "Features have Views folders") {
        app.checkFolderLayout(matching: "Sources/App/*", containing: ["Views"])
      }
      Rule("paths", "View models belong in ViewModels") {
        app.types.suffixed("ViewModel").violations(outsidePaths: ["Sources/App/*/ViewModels/**"])
      }
      """,
      "Sources/App/Orders/Models/OrderViewModel.swift": "class OrderViewModel {}",
    ])
    let program = try await loadedProgram(
      in: project,
      rulesFile: "Bylaws.swift"
    )
    let folderRule = try #require(program.rules.first { $0.id == "folders" })
    let pathRule = try #require(program.rules.first { $0.id == "paths" })
    #expect(try await folderRule.violations().count == 2)
    #expect(try await pathRule.violations().offenders
      .map(\.name) == ["OrderViewModel"])
  }

  @Test("Folder checks return the same findings in Swift and portable rules")
  func layoutFindings() async throws {
    let project = try rulesProject(
      rules: """
      Rule("features", "Features contain the required folders") {
        try await app.checkFolderLayout(
          matching: "Sources/App/*", containing: ["Models", "ViewModels", "Views"]
        )
      }
      """,
      sources: [
        "Sources/App/Orders/Models/Order.swift": "struct Order {}",
        "Sources/App/Orders/Extra/readme.txt": "",
      ]
    )
    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)
    let app = Codebase(root: .directory(project.rootURL.path))
    let native = try await app.checkFolderLayout(
      matching: "Sources/App/*", containing: ["Models", "ViewModels", "Views"]
    ).findings(reportedAt: rule.location)
    let interpreted = try await rule.findings()
    #expect(interpreted.violations == native.violations)
    #expect(interpreted.warnings == native.warnings)
    #expect(interpreted.violations.count == 3)
  }

  @Test("Placement checks return the same declarations", arguments: [
    #""Sources/App/*/ViewModels/**""#,
    #"["Sources/App/*/ViewModels/**"]"#,
  ])
  func placementFindings(argument: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("view-models", "View models belong in ViewModels") {
        try await app.types.suffixed("ViewModel").violations(
          outsidePaths: \(argument)
        )
      }
      """,
      sources: [
        "Sources/App/Orders/ViewModels/OrderViewModel.swift": "class OrderViewModel {}",
        "Sources/App/Orders/Views/MisplacedViewModel.swift": "class MisplacedViewModel {}",
      ]
    )
    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)
    let app = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"]
    )
    let selection = try await app.types.suffixed("ViewModel")
    let native = Violations(
      outsidePaths: ["Sources/App/*/ViewModels/**"],
      in: selection
    ).erased()
    let interpreted = try await rule.violations()
    #expect(interpreted == native)
    #expect(interpreted.offenders.map(\.name) == ["MisplacedViewModel"])
  }

  @Test("A typed helper returns a folder check and exposes its paths")
  func typedHelper() async throws {
    let project = try rulesProject(
      rules: """
      Rule("features", "Features have a Views folder") {
        let check = try await checkViews(app)
        let correct = check.matchedFolders == ["Sources/App/Orders"]
          && check.missingFolders == ["Sources/App/Orders/Views"]
          && check.unexpectedFolders == ["Sources/App/Orders/Models"]
        return try await app.files.violations(of: Matcher<SourceFile>("report the folder paths") { _ in correct })
      }
      """,
      sources: ["Sources/App/Orders/Models/A.swift": "struct A {}"]
    )
    let rules = try String(
      contentsOf: project.fileURL(for: "ProjectRules.swift"),
      encoding: .utf8
    )
    try project.write("""
    \(rules)
    import Bylaws
    func checkViews(_ app: Codebase) async throws -> FolderLayoutCheck {
      try await app.checkFolderLayout(matching: "Sources/App/*", containing: ["Views"])
    }
    """, to: "ProjectRules.swift")
    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)
    let result = try await rule.violations()
    #expect(result.isEmpty)
    #expect(result.checkedCount == 1)
  }
}
