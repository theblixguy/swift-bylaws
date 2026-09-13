import BylawsCore
import BylawsInterpreter
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable selection inspection")
struct SelectionInspectionRuleTests {
  @Test("Runtime filters record removed declarations", arguments: [
    #".where(\.isFinal)"#,
    #".where(Matcher<Class>("be final") { $0.isFinal })"#,
    #".suffixed("View")"#,
  ])
  func filterSteps(filter: String) async throws {
    let project = try TemporaryProject(files: [
      "ProjectRules.swift": """
      import Bylaws
      let app = Codebase(including: ["Sources/**"])
      let rules: [Rule] = [
        Rule("views", "Views are final") {
          let views = try await app.classes\(filter)
          return views.violations(of: .isFinal)
        }
      ]
      """,
      "Sources/App.swift": "final class OrderView {}\nclass OrderModel {}",
    ])
    let program = try await loadedProgram(in: project)

    let result = try await #require(program.rules.first).inspect()

    #expect(result.selections.count == 2)
    #expect(result.selections.last?.selected.map(\.name) == ["OrderView"])
    #expect(result.selections.last?.excluded.map(\.name) == ["OrderModel"])
  }

  @Test("Selection filters reject non-Boolean key paths")
  func nonBooleanKeyPath() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": #"""
      import Bylaws
      let app = Codebase(including: ["Sources/**"])
      let rules: [Rule] = [
        Rule("views", "Views are final") {
          let views = try await app.classes.where(\.name)
          return views.violations(of: .isFinal)
        }
      ]
      """#,
      "Sources/App.swift": "final class OrderView {}",
    ])
    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)

    #expect(program.errors
      .contains { $0.message.contains("the key path must be Bool") })
  }
}
