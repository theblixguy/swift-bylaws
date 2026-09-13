import BylawsIndexStore
import BylawsPaths
import Testing

@Suite("Index store candidates", .tags(.indexStore))
struct IndexStoreCandidatesTests {
  @Test("Package stores list the direct configurations before triples")
  func packageStoresOrderDirectConfigurationsFirst() {
    let build = LexicalFilePath("/pkg/.build")
    let stores = IndexStoreCandidates.packageStores(
      inBuildDirectory: build,
      entries: ["x86_64-apple-macosx", "index-build", "arm64-apple-macosx"]
    ).map(\.string)
    #expect(
      stores == [
        "/pkg/.build/debug/index/store",
        "/pkg/.build/release/index/store",
        "/pkg/.build/arm64-apple-macosx/debug/index/store",
        "/pkg/.build/arm64-apple-macosx/release/index/store",
        "/pkg/.build/x86_64-apple-macosx/debug/index/store",
        "/pkg/.build/x86_64-apple-macosx/release/index/store",
      ]
    )
  }

  @Test("The Derived Data search goes up at most six levels")
  func derivedDataStoresStopAtTheSearchDepth() {
    let stores = IndexStoreCandidates.derivedDataStores(
      above: LexicalFilePath("/a/b/c/d/e/f/g/h")
    )
    #expect(stores.count == 12)
    #expect(stores.first?.string == "/a/b/c/d/e/f/g/h/Index.noindex/DataStore")
    #expect(stores.last?.string == "/a/b/c/Index/DataStore")
  }

  @Test("The running build's store is next to its configuration directory")
  func runningBuildStoreUsesTheConfigurationDirectory() {
    let store = IndexStoreCandidates.runningBuildStore(
      besideExecutableAt: LexicalFilePath(
        "/pkg/.build/arm64/release/Tests.xctest/Contents/MacOS/Tests"
      )
    )
    #expect(store?.string == "/pkg/.build/arm64/release/index/store")
  }

  @Test("The editor's build is not the running build")
  func runningBuildStoreSkipsTheEditorBuild() {
    let store = IndexStoreCandidates.runningBuildStore(
      besideExecutableAt: LexicalFilePath(
        "/pkg/.build/index-build/arm64/debug/Tests"
      )
    )
    #expect(store == nil)
  }
}
