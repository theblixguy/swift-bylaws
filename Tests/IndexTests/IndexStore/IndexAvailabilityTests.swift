import BylawsIndexStore
import Foundation
import Testing

@Suite("Index integration availability")
struct IndexAvailabilityTests {
  @Test(
    "A required build supplies a readable compiler index",
    .enabled(
      if: ProcessInfo.processInfo.environment[
        "BYLAWS_REQUIRE_INDEX_STORE"
      ] == "1",
      "This build does not require index integration."
    )
  )
  func requiredBuildSuppliesIndex() throws {
    _ = try #require(ToolchainPaths.activeCompilerPath())
    _ = try #require(IndexStoreLocation.toolchainLibraryPath())
    let store = try IndexStore(path: IndexUnderTest.storePath())
    #expect(!store.unitNames().isEmpty)
  }
}
