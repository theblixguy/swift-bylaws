import Bylaws
import BylawsCore
import BylawsInterpreter
import BylawsTestSupport
import Foundation
import Testing

@Suite("Test bridge")
struct BridgeTests {
  @Test(
    "Advisory violations pass without trait",
    arguments: try await Self.store.value.rules
  )
  func advisoryDowngrades(_ rule: Rule) async throws {
    try await rule.report()
  }

  private static let store = Task {
    let project = try advisoryDocumentationProject()
    let rules = await RuleProgram.discovered(atRoot: project.rootURL.path).rules
    return RuleStore(retainedProject: project, rules: rules)
  }

  private struct RuleStore {
    let retainedProject: TemporaryProject
    let rules: [Rule]
  }
}
