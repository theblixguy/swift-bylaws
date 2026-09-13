import BylawsCore
import BylawsIndex
import BylawsIndexStore
import Testing

@Suite("Project index errors")
struct ProjectIndexErrorTests {
  @Test(
    "The description is the wrapped error's message",
    arguments: [
      (
        ProjectIndexError.unreadableCodebase(
          .rootNotFound(searchedFrom: "/project/Sources")
        ),
        CodebaseError.rootNotFound(searchedFrom: "/project/Sources").description
      ),
      (
        .indexUnavailable(
          .unsupportedLibrary(symbol: "indexstore_store_create")
        ),
        IndexStoreError.unsupportedLibrary(symbol: "indexstore_store_create")
          .description
      ),
    ]
  )
  func describesTheWrappedError(error: ProjectIndexError, expected: String) {
    #expect(error.description == expected)
  }

  @Test("Errors with different wrapped values are not equal")
  func distinguishesWrappedValues() {
    let missing = ProjectIndexError.indexUnavailable(
      .missingStore(searched: ["/a"])
    )
    let other = ProjectIndexError.indexUnavailable(
      .missingStore(searched: ["/b"])
    )
    #expect(missing != other)
    #expect(missing == .indexUnavailable(.missingStore(searched: ["/a"])))
  }
}
