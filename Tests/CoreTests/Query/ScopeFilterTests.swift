import Bylaws
import Testing

@Suite("Scope filters")
struct ScopeFilterTests {
  @Test("A scope directory outside the root warns the rule")
  func scopeOutsideRootWarns() async throws {
    let codebase = Codebase(root: .sources([
      "Sources/App/A.swift": "import UIKit\nfinal class A {}",
    ]))
    let rule = Rule("scope", "Files avoid UIKit") {
      try await codebase.files
        .under("../Elsewhere")
        .violations(matching: .imports("UIKit"))
    }

    let findings = try await rule.findings()

    #expect(findings.violations.isEmpty)
    #expect(findings.warnings.count == 1)
    #expect(
      findings.warnings.first?.message
        == "'../Elsewhere' is outside the codebase root"
    )
  }

  @Test("A scope directory inside the root warns nothing")
  func scopeInsideRootIsSilent() async throws {
    let codebase = Codebase(root: .sources([
      "Sources/App/A.swift": "import UIKit\nfinal class A {}",
    ]))
    let rule = Rule("scope", "Files avoid UIKit") {
      try await codebase.files
        .under("Sources/App")
        .violations(matching: .imports("UIKit"))
    }

    let findings = try await rule.findings()

    #expect(findings.violations.count == 1)
    #expect(findings.warnings.isEmpty)
  }
}
