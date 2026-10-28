import Testing

@Suite("Rule inspection command")
struct CLIInspectionProcessTests {
  @Test(
    "Rule inspection lists selected and excluded declarations",
    arguments: [false, true]
  )
  func selections(runtime: Bool) throws {
    let body = if runtime {
      """
      let views = try await app.classes.suffixed("View")
      return views.violations(of: .isFinal)
      """
    } else {
      "app.classes.suffixed(\"View\").violations(of: .isFinal)"
    }
    let project = try CLIProcessProject(
      source: "final class OrderView {}\nclass OrderModel {}",
      rules: """
      import Bylaws
      import Testing
      let app = Codebase(including: ["Sources/**"])
      \(runtime ? "let projectRules: [Rule] = [" : "")
      Rule("views", "Views are final") {
        \(body)
      }
      \(runtime ? "]" : "")
      """
    )

    let result = try project.runRules("--explain", "views")

    #expect(result.status == 0)
    #expect(result.standardOutput.contains("Selected: 1"))
    #expect(result.standardOutput.contains("Excluded: 1"))
    #expect(result.standardOutput
      .contains("Sources/App/App.swift:1:13 OrderView"))
    #expect(result.standardOutput.contains("OrderModel"))
    #expect(result.standardOutput.contains("Violations: 0"))
  }

  @Test("Unknown rule ID reports a setup error")
  func unknownRule() throws {
    let project = try CLIProcessProject(
      source: "class Order {}",
      rules: CLIProcessMock.finalClassesRule
    )

    let result = try project.runRules("--explain", "missing")

    #expect(result.status == 2)
    #expect((result.standardError + result.standardOutput)
      .contains("cannot find rule 'missing'"))
  }

  @Test("Inspection succeeds when a rule reports violations")
  func violations() throws {
    let project = try CLIProcessProject(
      source: "class Order {}",
      rules: CLIProcessMock.finalClassesRule
    )

    let result = try project.runRules("--explain", "final-classes")

    #expect(result.status == 0)
    #expect(result.standardOutput.contains("Violations: 1"))
  }
}
