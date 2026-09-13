import BylawsCore
import Foundation
import Testing

@Suite("Error descriptions")
struct ErrorDescriptionTests {
  @Test(
    "The localized description is the description",
    arguments: [
      CodebaseError.notADirectory(path: "/project/Package.swift"),
      LayeringError.duplicateLayer(name: "Core"),
      LayeringCheckError.invalidLayering(.duplicateLayer(name: "Core")),
    ] as [any DescribedError]
  )
  func localizesTheDescription(error: any DescribedError) {
    #expect(error.localizedDescription == error.description)
  }

  @Test("A rule error's localized description is its description")
  func localizesARuleError() {
    let error = RuleError(rule: Rule.ID("noSingletons"), cause: .cancelled)
    #expect(error.localizedDescription == error.description)
  }
}

typealias DescribedError = CustomStringConvertible & Error & Sendable
