import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Rule scopes")
struct ScopeTests {
  @Test("Loaded rules include their optional scopes")
  func loadedRulesKeepScopesAttached() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": finalClassRuleSource,
    ])
    let discovered = await RuleProgram.discovered(atRoot: project.rootURL.path)
    let rule = try #require(discovered.rules.first)
    let scope = RuleScope(
      id: rule.id,
      directory: "Sources",
      excludedSubtrees: []
    )

    let program = RuleProgram(
      loadedRules: [
        .init(rule: rule, scope: scope),
        .init(unscoped: rule),
      ],
      diagnostics: []
    )

    #expect(program.loadedRules.count == 2)
    #expect(program.loadedRules[0].scope?.directory == "Sources")
    #expect(program.loadedRules[1].scope == nil)
    #expect(program.rules.count == 2)
    #expect(program.scopes.count == 1)
    #expect(program.rules(applyingTo: "Sources/A.swift").count == 1)
  }

  @Test("An override's scope carries its declared reason")
  func overrideScopeCarriesItsReason() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": finalClassRuleSource,
      "Modules/Billing/Package.swift": "// swift-tools-version: 6.0",
      "Modules/Billing/Bylaws.swift": """
      let billing = Codebase(including: ["**"])
      Override("r", reason: "billing ships open classes") {
        billing.classes.violations(of: .isPublic)
      }
      """,
      "Modules/Billing/Sources/A.swift": "class A {}",
    ])
    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)

    let inBilling = program.loadedRules(
      applyingTo: "Modules/Billing/Sources/A.swift"
    )
    #expect(
      inBilling.map(\.scope?.overrideReason)
        == ["billing ships open classes"]
    )
    #expect(
      program.loadedRules(applyingTo: "Sources/App/B.swift")
        .allSatisfy { $0.scope?.overrideReason == nil }
    )
  }

  @Test("Rule selection respects the hierarchy's excluded scopes")
  func rulesFollowExcludedScopes() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": finalClassRuleSource,
      "Modules/Billing/Package.swift": "// swift-tools-version: 6.0",
      "Modules/Billing/Bylaws.swift": """
      let billing = Codebase(including: ["**"])
      Override("r", reason: "billing differs") {
        billing.classes.violations(of: .isPublic)
      }
      Rule("billing-only", "Billing rule") {
        billing.classes.violations(of: .isFinal)
      }
      """,
      "Modules/Billing/Sources/A.swift": "class A {}",
      "Sources/App/B.swift": "class B {}",
    ])
    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)

    let atRoot = program.rules(applyingTo: "Sources/App/B.swift")
    #expect(atRoot.map(\.id) == ["r"])
    let rootRule = try #require(atRoot.first)
    #expect(rootRule.location.filePath.hasSuffix("Bylaws.swift"))
    #expect(
      atRoot.first?.location.filePath.contains("Billing") == false
    )

    let inBilling = program.rules(applyingTo: "Modules/Billing/Sources/A.swift")
    #expect(inBilling.map(\.id) == ["r", "billing-only"])
    #expect(
      try #require(inBilling.first).location.filePath.contains("Billing")
    )
  }

  @Test("An invalid override leaves the root rule in force")
  func invalidOverrideLeavesRootRuleInForce() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": finalClassRuleSource,
      "Modules/Billing/Package.swift": "// swift-tools-version: 6.0",
      "Modules/Billing/Bylaws.swift": """
      let billing = Codebase(including: ["**"])
      Override("r", reason: "billing differs") {
        billing.classes.violations(of: .unknown)
      }
      """,
      "Modules/Billing/Sources/A.swift": "class A {}",
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)

    #expect(program.errors.count == 1)
    let rules = program.rules(
      applyingTo: "Modules/Billing/Sources/A.swift"
    )
    #expect(rules.map(\.id) == ["r"])
    #expect(try #require(rules.first).location.filePath == project.rootURL.path
      + "/Bylaws.swift")
  }
}
