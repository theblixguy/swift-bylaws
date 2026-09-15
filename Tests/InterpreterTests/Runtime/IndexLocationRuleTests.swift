import BylawsCore
import BylawsInterpreter
import BylawsPaths
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable source-position index queries")
struct IndexLocationRuleTests {
  @Test("Exact index lookups preserve locations and symbol identities")
  func exactLookup() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      import Bylaws
      import BylawsIndex
      let codebase = Codebase(including: ["Sources/**"])
      let rules: [Rule] = [
        Rule("index-position", "Source positions identify indexed symbols") {
          let index = try await codebase.projectIndex(modules: ["BylawsSemantics"])
          let known = index.occurrences(of: "Located")
          for reference in known {
            let found = index.occurrences(at: reference.location)
            Violations(rule: "be absent", offenders: found, checkedCount: 1)
          }
        },
      ]
      """,
      "Sources/App.swift": "struct App {}",
    ])
    let program = await RuleProgram.loaded(
      fromFiles: [LexicalFilePath(project.rootURL
          .appending(path: "Bylaws.swift").path)],
      parseCachePolicy: .disabled,
      indexProvider: RuntimeIndexProviderMock()
    )
    try program.requireNoDiagnostics()
    let findings = try await #require(program.rules.first).findings()
    #expect(findings.violations.count == 2)
    #expect(findings.violations.offenders.map(\.name) == [
      "CoreConformer",
      "UIConformer",
    ])
    #expect(findings.violations.offenders.map(\.location.column) == [7, 7])
  }
}
