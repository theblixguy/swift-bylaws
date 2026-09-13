import BylawsCore
import BylawsIndex
import BylawsIndexStore
import Testing

@Suite("Indexed layering errors")
struct IndexedLayeringErrorTests {
  @Test(
    "The description is the wrapped error's message",
    arguments: [
      (
        IndexedLayeringError.invalidLayering(.duplicateLayer(name: "Core")),
        LayeringError.duplicateLayer(name: "Core").description
      ),
      (
        .unreadableCodebase(.notADirectory(path: "/project/Package.swift")),
        CodebaseError.notADirectory(path: "/project/Package.swift").description
      ),
      (
        .indexUnavailable(.missingStore(searched: ["/project/.build"])),
        IndexStoreError.missingStore(searched: ["/project/.build"]).description
      ),
    ]
  )
  func describesTheWrappedError(
    error: IndexedLayeringError,
    expected: String
  ) {
    #expect(error.description == expected)
  }

  @Test(
    "A project index error converts to the matching layering case",
    arguments: [
      (
        ProjectIndexError.unreadableCodebase(
          .rootNotFound(searchedFrom: "/project/Sources")
        ),
        IndexedLayeringError.unreadableCodebase(
          .rootNotFound(searchedFrom: "/project/Sources")
        )
      ),
      (
        .indexUnavailable(.missingLibrary),
        .indexUnavailable(.missingLibrary)
      ),
    ]
  )
  func convertsAProjectIndexError(
    source: ProjectIndexError,
    expected: IndexedLayeringError
  ) {
    #expect(IndexedLayeringError(source) == expected)
  }
}
