import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import Foundation
import Testing

@Suite("Error descriptions")
struct ErrorDescriptionTests {
  private static let diagnostic = Diagnostic(
    severity: .error,
    location: DeclarationLocation(
      filePath: "/project/Bylaws.swift",
      line: 3,
      column: 5,
      utf8Offset: 40
    ),
    message: "unknown rule 'noSingletons'"
  )

  @Test(
    "The localized description is the description",
    arguments: [
      diagnostic,
      BylawsFileError(diagnostics: [diagnostic]),
      RuleDiscoveryError
        .invalidRules(BylawsFileError(diagnostics: [diagnostic])),
      RuleDiscoveryError
        .unresolvedRoot(.rootNotFound(searchedFrom: "/project")),
    ] as [any DescribedError]
  )
  func localizesTheDescription(error: any DescribedError) {
    #expect(error.localizedDescription == error.description)
  }
}

typealias DescribedError = CustomStringConvertible & Error & Sendable
