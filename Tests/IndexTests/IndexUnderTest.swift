import BylawsCore
import BylawsIndex
import BylawsIndexStore
import BylawsSemantics

enum IndexUnderTest {
  static let modules: Set<String> = [
    "Bylaws", "BylawsCore", "BylawsSemantics", "BylawsIndex",
    "BylawsIndexStore",
  ]

  static let codebase = Codebase(
    root: .automatic(),
    including: ["Sources/**"],
    swiftLanguageMode: .v6
  )

  // The index suite must survive a rename in the product sources.
  static let testModules = Codebase(
    root: .automatic(),
    including: ["Tests/TestModules/**"],
    swiftLanguageMode: .v6
  )

  static let testModuleNames: Set<String> = [
    "PortableRuleSupport", "PortableRules",
  ]

  static let isAvailable = IndexStoreLocation.toolchainLibraryPath() != nil
    && (try? storePath()) != nil

  static func storePath() throws -> String {
    try IndexStoreLocation.path(forPackageContaining: #filePath)
  }

  static func index() async throws -> ProjectIndex {
    try await codebase.projectIndex(modules: modules)
  }

  static func index(
    through cache: ProjectIndexCache
  ) async throws -> ProjectIndex {
    try await cache.index(
      for: codebase,
      modules: modules,
      unitOutputFiles: nil
    )
  }
}
