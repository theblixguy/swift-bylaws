import BylawsSemantics
import Foundation
import Testing

@Suite("Error descriptions")
struct ErrorDescriptionTests {
  @Test(
    "The localized description is the description",
    arguments: [
      ParseError.didNotParse(path: "/project/Sources/App.swift"),
      .unreadable(path: "/project/Sources/App.swift", reason: "not UTF-8"),
    ]
  )
  func localizesTheDescription(error: ParseError) {
    #expect(error.localizedDescription == error.description)
  }
}
