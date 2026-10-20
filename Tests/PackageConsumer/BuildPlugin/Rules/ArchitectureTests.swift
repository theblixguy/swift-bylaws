import Bylaws
import BylawsInterpreter
import Testing

@Test("Discovered source rules pass", arguments: try await Rule.discovered())
func architecture(_ rule: Rule) async throws {
  try await rule.report()
}
