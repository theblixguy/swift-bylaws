import BylawsIndexStore
import BylawsPaths
import Testing

@Suite("Index store candidates", .tags(.indexStore))
struct IndexStoreCandidatesTests {
  @Test("Package stores include both build-system layouts")
  func packageStoresOrderDirectConfigurationsFirst() {
    let build = LexicalFilePath("/pkg/.build")
    let stores = IndexStoreCandidates.packageStores(
      inBuildDirectory: build,
      entries: ["x86_64-apple-macosx", "index-build", "arm64-apple-macosx"]
    ).map(\.string)
    #expect(
      stores == [
        "/pkg/.build/out",
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

  @Test("Swift Build executables identify shared index directory", arguments: [
    (path: "/pkg/.build/out/Products/Debug/tool", store: "/pkg/.build/out"),
    (path: "/pkg/.build/out/Products/Release/tool", store: "/pkg/.build/out"),
    (
      path: "/scratch/out/Products/Debug/Tests.xctest/Contents/MacOS/Tests",
      store: "/scratch/out"
    ),
    (path: "/scratch/out/Products/debug/Tests.xctest", store: "/scratch/out"),
  ])
  func swiftBuildExecutable(path: String, store: String) {
    let found = IndexStoreCandidates.runningBuildStore(
      besideExecutableAt: LexicalFilePath(path)
    )
    #expect(found?.string == store)
  }

  @Test("Swift Build editor indexes remain excluded")
  func swiftBuildEditor() {
    #expect(IndexStoreCandidates.runningBuildStore(
      besideExecutableAt: LexicalFilePath(
        "/pkg/.build/index-build/out/Products/Debug/tool"
      )
    ) == nil)
  }

  @Test("Nested executables retain build directory", arguments: [
    (
      directory: "/pkg/.build/arm64/debug",
      store: "/pkg/.build/arm64/debug/index/store"
    ),
    (directory: "/scratch/out/Products/Debug", store: "/scratch/out"),
  ])
  func nestedExecutable(directory: String, store: String) {
    let nested = Array(repeating: "nested", count: 12).joined(separator: "/")
    let found = IndexStoreCandidates.runningBuildStore(
      besideExecutableAt: LexicalFilePath("\(directory)/\(nested)/tool")
    )
    #expect(found?.string == store)
  }

  @Test("Unrecognised paths end without a store", arguments: [
    "/tool", "/", "tool", ".", "",
  ])
  func unrecognisedPath(path: String) {
    #expect(IndexStoreCandidates.runningBuildStore(
      besideExecutableAt: LexicalFilePath(path)
    ) == nil)
  }

  @Test("Nearest build configuration wins")
  func nearestConfiguration() {
    let found = IndexStoreCandidates.runningBuildStore(
      besideExecutableAt: LexicalFilePath(
        "/release/project/.build/arm64/debug/Tests.xctest/Contents/MacOS/Tests"
      )
    )
    #expect(found?.string == "/release/project/.build/arm64/debug/index/store")
  }
}
