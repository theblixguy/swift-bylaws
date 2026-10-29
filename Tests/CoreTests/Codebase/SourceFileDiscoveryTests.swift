import BylawsPaths
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
    #expect(Set(result.relativeParentDirectories) == [
      LexicalFilePath("Sources/Feature"), LexicalFilePath("Sources"),
    ])
  }

  @Test("Selected files share parent directories and retain root files")
  func selectedParents() async throws {
    let project = try TemporaryProject(files: [
      "Root.swift": "struct Root {}",
      "Sources/App/One.swift": "struct One {}",
      "Sources/App/Two.swift": "struct Two {}",
      "Sources/Hidden/Other.swift": "struct Other {}",
    ])
    let result = await SourceFileDiscovery.paths(
      under: project.rootURL.path,
      including: [], excluding: ["**/Hidden/**"]
    )

    #expect(result.failures.isEmpty)
    #expect(result.paths.count == 3)
    #expect(result.relativeParentDirectories == [
      LexicalFilePath(""), LexicalFilePath("Sources/App"),
    ])
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
