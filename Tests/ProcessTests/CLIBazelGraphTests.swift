import BylawsTestSupport
import Testing

@Suite("Bazel graph from the CLI")
struct CLIBazelGraphTests {
  @Test("Empty query results load through CLI")
  func emptyExport() throws {
    let project = try CLIProcessProject(
      source: "",
      rules: """
      let codebase = Codebase()
      let projectRules: [Rule] = [
        Rule("graph", "Graph empty") {
          let graph = try await codebase.bazelGraph(from: "graph.json")
          return Violations(rule: "have no targets", offenders: graph.targets, checkedCount: graph.targets.count)
        },
      ]
      """,
      extraFiles: ["MODULE.bazel": "", "graph.json": "{}"],
      writesProjectMarker: false
    )
    let result = try project.run("--format", "json")
    #expect(result.status == 0)
    #expect(!result.standardOutput.contains("cannot read the Bazel graph"))
  }

  @Test("Bazel violations identify the BUILD file")
  func dependencyViolation() throws {
    let project = try CLIProcessProject(
      source: "",
      rules: """
      let codebase = Codebase()
      let projectRules: [Rule] = [
        Rule("database", "Features independent of database") {
          let graph = try await codebase.bazelGraph(from: "graph.json")
          let features = graph.targets.filter { $0.tags.contains("feature") }
          let offenders = features.filter { feature in
            graph.transitiveTargetDependencies(of: feature).contains {
              $0.label == "//storage:Database"
            }
          }
          return Violations(
            rule: "avoid database dependencies",
            offenders: offenders,
            checkedCount: features.count
          )
        },
      ]
      """,
      extraFiles: ["MODULE.bazel": "", "graph.json": BazelGraphMock.json],
      writesProjectMarker: false
    )
    let result = try project.run("--format", "xcode")
    #expect(result.status == 1)
    #expect(result.standardOutput.contains("features/BUILD.bazel:8:3:"))
    #expect(result.standardOutput.contains("//features:Orders"))
  }

  @Test("Broken Bazel exports fail the CLI")
  func brokenExport() throws {
    let project = try CLIProcessProject(
      source: "",
      rules: """
      let codebase = Codebase()
      let projectRules: [Rule] = [
        Rule("graph", "Bazel graph readable") {
          let graph = try await codebase.bazelGraph(from: "graph.json")
          return Violations(
            rule: "have no targets",
            offenders: graph.targets,
            checkedCount: graph.targets.count
          )
        },
      ]
      """,
      extraFiles: ["MODULE.bazel": "", "graph.json": #"{"target": []}"#],
      writesProjectMarker: false
    )
    let result = try project.run("--format", "json")
    #expect(result.status == 2)
    #expect(result.standardOutput.contains("cannot read the Bazel graph"))
    #expect(result.standardOutput.contains("--transitions=lite"))
  }
}
