import BylawsCore
import BylawsInterpreter
import BylawsTestSupport
import Testing

@Suite("Portable Bazel build settings")
struct BazelConfigurationRuleTests {
  @Test("Typed configuration helpers read grouped options")
  func typedConfiguration() async throws {
    let project = try TemporaryProject(files: [
      "MODULE.bazel": "",
      "graph.json": BazelGraphMock.settingsJSON,
      "Bylaws.swift": """
      let codebase = Codebase()
      func permitted(_ configuration: BazelGraph.Configuration) -> Bool {
        configuration.isTool && configuration.checksum == "exec"
          && configuration.buildOptions["CoreOptions"]?["compilation_mode"] == "opt"
          && configuration.buildOptions["PlatformOptions"]?["platforms"] == "[//platforms:phone]"
          && configuration.buildOptions["user-defined"]?["//settings:api"] == "v2"
      }
      let projectRules: [Rule] = [
        Rule("tools", "Tools use release settings") {
          let graph = try await codebase.bazelGraph(from: "graph.json")
          let offenders = graph.targets.filter { target in
            guard let configuration = target.configuration else { return true }
            return !permitted(configuration)
          }
          return Violations(rule: "use release settings", offenders: offenders, checkedCount: graph.targets.count)
        },
      ]
      """,
    ])
    let program = try await loadedProgram(
      in: project,
      rulesFile: "Bylaws.swift"
    )
    let rule = try #require(program.rules.first)
    let violations = try await rule.violations()
    #expect(violations.isEmpty)
    #expect(violations.checkedCount == 1)
  }
}
