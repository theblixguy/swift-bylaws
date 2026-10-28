import Testing

@Suite("Source-only rule checks")
struct CLISourceOnlyProcessTests {
  @Test("Source-only checks can discover dependency groups")
  func dependencyGroups() throws {
    let project = try CLIProcessProject(
      source: "final class App {}",
      rules: """
      let app = Codebase(including: ["Sources/**"])
      let rules: [Rule] = [
        Rule("groups") {
          let groups = try await app.dependencyGroups(inFoldersMatching: "Sources")
          let names = groups.map { $0.name }
          return Violations<Offender>(rule: "discover groups", offenders: [], checkedCount: names.count)
        }
      ]
      """
    )

    let result = try project.run("--source-only")

    #expect(result.status == 0)
    #expect(!result.standardOutput.contains("no groups"))
  }

  @Test("Source-only checks retain source violations")
  func sourceViolation() throws {
    let project = try CLIProcessProject(
      source: "class App {}",
      rules: CLIProcessMock.finalClassesRule
    )

    let result = try project.run("--source-only")

    #expect(result.status == 1)
    #expect(result.standardOutput.contains("final-classes"))
  }

  @Test("Source-only checks reject index queries", arguments: [
    "app.projectIndex()",
    "app.definitions(of: \"App\")",
    "app.checkDependencies(from: [\"Sources/**\"], allowingReferencesTo: [])",
    "app.checkDependencyCycles(between: [DependencyGroup(\"App\", files: [\"Sources/**\"])])",
  ])
  func indexQuery(_ query: String) throws {
    let project = try CLIProcessProject(
      source: "final class App {}",
      rules: """
      let app = Codebase(including: ["Sources/**"])
      let rules: [Rule] = [
        Rule("index-check", "App has an index") {
          let index = try await \(query)
          return try await app.classes.violations(of: .isFinal)
        },
      ]
      """
    )

    let result = try project.run("--source-only")

    #expect(result.status != 0)
    #expect(result.standardOutput
      .contains("index queries need a completed build"))
    #expect(result.standardOutput.contains("without --source-only"))
  }
}
