import BylawsTestSupport
import Foundation
import Testing
@testable import BylawsCore

@Suite("Source file discovery paths")
struct SourceFileDiscoveryTests {
  @Test(
    "Root aliases preserve selected paths",
    arguments: ["", "/", "/Sources/../"]
  )
  func rootAlias(suffix: String) async throws {
    let project = try TemporaryProject(files: [
      "Sources/Feature/Café.swift": "struct Value {}",
      "Sources/File..swift": "struct Other {}",
      "Sources/Excluded/Hidden.swift": "struct Hidden {}",
      "Elsewhere/Other.swift": "struct Unrelated {}",
    ])

    let result = await SourceFileDiscovery.paths(
      under: project.rootURL.path + suffix,
      including: ["Sources/**"], excluding: ["**/Excluded/**"]
    )

    #expect(result.failures.isEmpty)
    #expect(result.paths.sorted() == [
      project.fileURL(for: "Sources/Feature/Café.swift").path,
      project.fileURL(for: "Sources/File..swift").path,
    ].sorted())
  }

  @Test(
    "Missing roots report normalised paths",
    arguments: ["Missing", "./Missing///"]
  )
  func missingRoot(relative: String) async throws {
    let project =
      try TemporaryProject(files: ["Value.swift": "struct Value {}"])

    let result = await SourceFileDiscovery.paths(
      under: project.rootURL.path + "/" + relative,
      including: [], excluding: []
    )

    #expect(result.paths.isEmpty)
    #expect(result.failures
      .map(\.path) == [project.fileURL(for: "Missing").path])
  }
}
