import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable check results")
struct CheckResultParityTests {
  @Test("Findings reject violation-only members", arguments: [
    "count", "isEmpty", "offenders", "rule", "checkedCount",
  ])
  func findingsMembers(member: String) async throws {
    let project = try packageDependencyProject(
      rulesFile: "ProjectRules.swift",
      rulesSource: """
      func inspect(_ value: Rule.Findings) -> Int {
        let result = value.\(member)
        return 0
      }
      let app = Codebase(including: ["Sources/**"])
      let projectRules: [Rule] = [
        Rule("package", "Dependencies match imports") {
          try await app.checkPackageDependencies()
        }
      ]
      """
    )
    let program = await RuleProgram.loaded(
      fromFiles: [.init(project.fileURL(for: "ProjectRules.swift").path)]
    )

    #expect(program.errors.contains {
      $0.message
        .contains("'\(member)' is not a supported member of Rule.Findings")
    })
  }

  @Test("Findings cannot be returned as typed violations")
  func findingsType() async throws {
    let project = try packageDependencyProject(
      rulesFile: "ProjectRules.swift",
      rulesSource: """
      func imports(_ value: Rule.Findings) -> Violations<Import> { value }
      let app = Codebase(including: ["Sources/**"])
      let projectRules: [Rule] = [
        Rule("package", "Dependencies match imports") {
          try await app.checkPackageDependencies()
        }
      ]
      """
    )
    let program = await RuleProgram.loaded(
      fromFiles: [.init(project.fileURL(for: "ProjectRules.swift").path)]
    )

    #expect(program.errors.contains {
      $0.message.contains("must return Violations<Import>, not Rule.Findings")
    })
  }

  @Test("Dependency count matches returned offenders")
  func dependencyCount() async throws {
    let project = try packageDependencyProject(
      rulesFile: "ProjectRules.swift",
      rulesSource: """
      let app = Codebase(including: ["Sources/**"])
      let projectRules: [Rule] = [
      Rule("counts", "Dependency counts agree") {
        let result = try await app.checkPackageDependencies().violations
        return try await app.types.violations(of: Matcher<NominalType>("have equal counts") {
          result.count == result.offenders.count
        })
      }
      ]
      """
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.isEmpty)
  }
}
