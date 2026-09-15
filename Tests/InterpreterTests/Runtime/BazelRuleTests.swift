import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable Bazel rules")
struct BazelRuleTests {
  @Test("Typed helpers query immediate Bazel dependencies")
  func typedHelper() async throws {
    let project = try TemporaryProject(files: [
      "MODULE.bazel": "",
      "graph.json": BazelGraphMock.json,
      "Bylaws.swift": """
      let codebase = Codebase()

      func dependencies(
        of target: BazelGraph.Target,
        in graph: BazelGraph
      ) -> [BazelGraph.Target] {
        graph.directTargetDependencies(of: target)
      }

      let projectRules: [Rule] = [
        Rule("direct", "Features use the store") {
          let graph = try await codebase.bazelGraph(from: "graph.json")
          let features = graph.targets.filter { $0.tags.contains("feature") }
          let offenders = features.filter { feature in
            !dependencies(of: feature, in: graph).contains {
              $0.label == "//services:Store"
                && $0.configuration == feature.configuration
                && $0.ruleClass == "swift_library"
            }
          }
          return Violations(
            rule: "depend on the store",
            offenders: offenders,
            checkedCount: features.count
          )
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
    #expect(violations.checkedCount == 2)
  }

  @Test(
    "Swift and CLI rules report the same Bazel targets",
    arguments: [false, true]
  )
  func dependencyRule(split: Bool) async throws {
    let project = try TemporaryProject(files: [
      "MODULE.bazel": "module(name = \"app\")",
      "graph.json": split ? BazelGraphMock.splitJSON : BazelGraphMock.json,
      "Bylaws.swift": """
      import Bylaws
      let codebase = Codebase()
      let projectRules: [Rule] = [Rule("feature-dependencies", "Features independent of database") {
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
      }]
      """,
    ])
    let codebase = Codebase(root: .directory(project.rootURL.path))
    let graph = try await codebase.bazelGraph(from: "graph.json")
    let features = graph.targets.filter { $0.tags.contains("feature") }
    let offenders = features.filter { feature in
      graph.transitiveTargetDependencies(of: feature).contains {
        $0.label == "//storage:Database"
      }
    }
    let native = Violations(
      rule: "avoid database dependencies",
      offenders: offenders,
      checkedCount: features.count
    ).erased()
    let program = try await loadedProgram(
      in: project,
      rulesFile: "Bylaws.swift"
    )
    let rule = try #require(program.rules.first)
    let interpreted = try await rule.violations()
    #expect(interpreted == native)
    #expect(interpreted.count == 1)
    #expect(interpreted.checkedCount == 2)
    #expect(interpreted.offenders.first?.location.line == 8)
  }
}
