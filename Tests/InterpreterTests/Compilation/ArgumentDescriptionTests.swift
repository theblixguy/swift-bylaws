import Testing
@testable import BylawsInterpreter

@Suite("Argument count descriptions")
struct ArgumentDescriptionTests {
  @Test("Argument count uses singular and plural forms", arguments: [
    (count: 0, text: "0 arguments"),
    (count: 1, text: "1 argument"),
    (count: 2, text: "2 arguments"),
  ])
  func countDescription(count: Int, text: String) {
    #expect(argumentCountDescription(count) == text)
  }
}
