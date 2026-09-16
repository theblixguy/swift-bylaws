import BylawsCore
import BylawsInterpreter
import BylawsTestSupport
import Testing

@Suite("Compiled name filter plans")
struct QueryFilterPlanTests {
  @Test("Name chains preserve findings and inspection steps")
  func names() async throws {
    let project = try TemporaryProject(files: [
      "ProjectRules.swift": #"""
      import Bylaws
      let app = Codebase(including: ["Sources/**"])
      let rules: [Rule] = [
        Rule("views", "Views are final") {
          try await app.classes
            .prefixed("Order").suffixed("View").excluding("Other")
            .violations(of: .isFinal)
        }
      ]
      """#,
      "Sources/App.swift": "class OrderView {}\nclass OrderModel {}\nclass Other {}",
    ])
    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)

    let findings = try await rule.findings()
    let inspection = try await rule.inspect()

    #expect(findings.violations.offenders.map(\.name) == ["OrderView"])
    #expect(inspection.findings.violations == findings.violations)
    #expect(inspection.selections.map(\.selected.count) == [3, 2, 1, 1])
  }
}
