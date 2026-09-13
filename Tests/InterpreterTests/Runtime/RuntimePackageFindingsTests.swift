import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable package findings")
struct RuntimePackageFindingsTests {
  @Test("Helpers return native package findings", arguments: [
    ([String](), ["App depends on Unused", "Domain"]),
    (["App"], []),
  ])
  func helperResult(
    ignoredTargets: [String],
    expectedNames: [String]
  ) async throws {
    let names = ignoredTargets.map { "\"\($0)\"" }.joined(separator: ", ")
    let project = try packageDependencyProject(
      rulesFile: "ProjectRules.swift",
      rulesSource: """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])

      func dependencies() async throws -> PackageDependencyCheck {
        try await app.checkPackageDependencies(ignoring: [\(names)])
      }

      let projectRules: [Rule] = [
        Rule("manifest", "Package dependencies match imports") {
          try await dependencies()
        },
      ]
      """
    )
    let program = try await loadedProgram(in: project)
    let interpreted = try await #require(program.rules.first).findings()
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"]
    )
    let native = try await codebase.checkPackageDependencies(
      ignoring: ignoredTargets
    ).findings(reportedAt: .start(of: "ProjectRules.swift"))

    #expect(interpreted.violations.offenders.compactMap(\.name)
      .sorted() == expectedNames)
    #expect(native.violations.offenders.compactMap(\.name)
      .sorted() == expectedNames)
    #expect(interpreted.violations.checkedCount == native.violations
      .checkedCount)
    #expect(interpreted.warnings.isEmpty)
    #expect(native.warnings.isEmpty)
  }
}
