import ArgumentParser
import Testing
@testable import PackageManifestSync

@Suite("Package manifest command")
struct PackageManifestSyncCommandTests {
  @Test("Artifact options parse in either order", arguments: [
    [
      "--plugin-url",
      "https://example.com/tool.zip",
      "--plugin-checksum",
      "abc",
      "--check",
    ],
    [
      "--check",
      "--plugin-checksum",
      "abc",
      "--plugin-url",
      "https://example.com/tool.zip",
    ],
  ])
  func parsesArtifactOptions(arguments: [String]) throws {
    let command = try PackageManifestSync.parse(arguments)

    #expect(command.check)
    #expect(command.pluginURL == "https://example.com/tool.zip")
    #expect(command.pluginChecksum == "abc")
  }

  @Test("Artifact options take both values", arguments: [
    ["--plugin-url", "https://example.com/tool.zip"],
    ["--plugin-checksum", "abc"],
  ])
  func rejectsIncompleteArtifact(arguments: [String]) {
    #expect(throws: (any Error).self) {
      _ = try PackageManifestSync.parse(arguments)
    }
  }
}
