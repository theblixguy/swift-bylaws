import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Folder rule scopes")
struct FolderScopeTests {
  @Test("A folder override excludes its subtree from the parent rule")
  func overriddenFolder() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("folders", "Features have Views folders") {
        app.checkFolderLayout(matching: "Sources/App/*", containing: ["Views"])
      }
      """,
      "Sources/App/Orders/Models/Order.swift": "struct Order {}",
      "Sources/App/Profile/Models/Profile.swift": "struct Profile {}",
      "Sources/App/Profile/Package.swift": "",
      "Sources/App/Profile/Bylaws.swift": """
      let feature = Codebase()
      Override("folders", reason: "Profile uses Models during migration") {
        feature.checkFolderLayout(matching: ".", containing: ["Models"])
      }
      """,
    ])
    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)
    try program.requireNoDiagnostics()
    #expect(program.rules.count == 2)
    let parent = try #require(program.rules.first {
      $0.location.filePath == project.fileURL(for: "Bylaws.swift").path
    })
    let result = try await parent.violations()
    #expect(result.offenders.map(\.name) == [
      "Sources/App/Orders/Views", "Sources/App/Orders/Models",
    ])
    let child = try #require(program.rules.first {
      $0.location.filePath == project
        .fileURL(for: "Sources/App/Profile/Bylaws.swift").path
    })
    #expect(try await child.violations().isEmpty)
  }
}
