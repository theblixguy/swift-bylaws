import BylawsCore
import BylawsSemantics
import SwiftSyntax
import Testing

@Suite("Cached language modes")
struct LanguageModeCacheTests {
  @Test("Disk cache separates language modes and retains syntax mode")
  func separateEntries() throws {
    let storage = try ParseCacheTestStorage()
    let source = "@available (swift, obsoleted: 1.0)\nstruct Legacy {}"
    let path = "/project/Legacy.swift"
    let file = try FileCollector.collect(
      source: source,
      path: path,
      swiftLanguageMode: .v5
    )
    storage.cache.store(file)

    let loaded = try #require(storage.cache.sourceFile(
      forSource: source,
      at: path,
      swiftLanguageMode: .v5
    ))
    #expect(loaded.swiftLanguageMode == .v5)
    #expect(loaded.withSyntax { !$0.hasError })
    #expect(storage.cache.sourceFile(
      forSource: source,
      at: path,
      swiftLanguageMode: .v6
    ) == nil)
  }
}
