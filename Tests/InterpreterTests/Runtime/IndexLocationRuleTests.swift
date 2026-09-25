import BylawsCore
import BylawsInterpreter
import BylawsPaths
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable source-position index queries")
struct IndexLocationRuleTests {
  @Test("Portable rules report DEBUG symbol uses outside DEBUG")
  func debugSymbolUses() async throws {
    let project = try TemporaryProject(files: [
      "MODULE.bazel": "",
      "Bylaws.swift": """
      import Bylaws
      import BylawsIndex
      let codebase = Codebase(
        including: ["Sources/**"], swiftLanguageMode: .v6
      )
      let rules: [Rule] = [
        Rule("debug-symbols", "DEBUG symbols used only inside DEBUG") {
          let debugBranches = try await codebase.compilationBranches.filter {
            $0.condition == "DEBUG"
          }
          let index = try await codebase.projectIndex()
          let definitions = index.definitions().filter {
            definition in debugBranches.contains {
              $0.contains(definition.location)
            }
          }
          let outside = index.references(to: definitions).filter {
            reference in !debugBranches.contains {
              $0.contains(reference.location)
            }
          }
          Violations(
            rule: "stay inside DEBUG",
            offenders: outside,
            checkedCount: 1
          )
        },
      ]
      """,
      "Sources/App.swift": """
      #if DEBUG
      func debugOnly() {}
      #endif
      func useDebugOnly() { debugOnly() }
      """,
    ])
    let sourcePath = project.fileURL(for: "Sources/App.swift").path
    let symbol = RuntimeIndexSymbol(
      usr: "s:App.debugOnly", name: "debugOnly", kind: .function
    )
    let provider = RuntimeIndexProviderMock(references: [
      RuntimeIndexReference(
        symbol: symbol, module: "App", file: sourcePath,
        line: 2, column: 6, roles: [.definition]
      ),
      RuntimeIndexReference(
        symbol: symbol, module: "App", file: sourcePath,
        line: 4, column: 22, roles: [.reference]
      ),
    ])
    let program = await RuleProgram.loaded(
      fromFiles: [LexicalFilePath(project.rootURL
          .appending(path: "Bylaws.swift").path)],
      parseCachePolicy: .disabled,
      indexProvider: provider
    )
    try program.requireNoDiagnostics()
    let findings = try await #require(program.rules.first).findings()
    #expect(findings.violations.offenders.map(\.name) == ["debugOnly"])
    #expect(findings.violations.offenders.map(\.location.line) == [4])
  }

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
        Rule("index-name", "Names find indexed references") {
          let index = try await codebase.projectIndex(modules: ["BylawsSemantics"])
          Violations(
            rule: "be absent",
            offenders: index.references(to: "Located"),
            checkedCount: 1
          )
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
    let named = try await #require(program.rules.last).findings()
    #expect(named.violations.count == 2)
  }
}
