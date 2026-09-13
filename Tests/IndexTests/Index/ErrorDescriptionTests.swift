import BylawsCore
import BylawsIndex
import BylawsIndexStore
import Foundation
import Testing

@Suite("Error descriptions")
struct ErrorDescriptionTests {
  @Test(
    "The localized description is the description",
    arguments: [
      IndexedLayeringError.invalidLayering(.duplicateLayer(name: "Core")),
      ProjectIndexError.indexUnavailable(.missingLibrary),
      IndexStoreError.missingStore(searched: ["/project/.build"]),
    ] as [any DescribedError]
  )
  func localizesTheDescription(error: any DescribedError) {
    #expect(error.localizedDescription == error.description)
  }
}

typealias DescribedError = CustomStringConvertible & Error & Sendable
