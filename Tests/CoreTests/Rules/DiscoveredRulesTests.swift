import Bylaws
import BylawsInterpreter
import Testing

@Suite("Discovered rules")
struct DiscoveredRulesTests {
  @Test(
    "Discovered project rules pass",
    arguments: try await Rule.discovered()
  )
  func followsRule(_ rule: Rule) async throws {
    try await rule.report()
  }
}
