import Foundation
import SwiftSyntaxArtifactCore
import Testing

@Suite("Artifact configuration")
struct ArtifactConfigurationTests {
  @Test("Derives SwiftSyntax major version")
  func derivesSwiftSyntaxMajorVersion() throws {
    try withTemporaryDirectory { directory in
      let configuration = try loadConfiguration(in: directory)

      #expect(configuration.swiftSyntaxMajorVersion == "604")
    }
  }

  @Test("Rejects mismatched Swift version")
  func rejectsMismatchedSwiftVersion() throws {
    try withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("configuration.json")
      try configurationJSON(compilerVersion: "6.3").write(
        to: url,
        atomically: true,
        encoding: .utf8
      )

      #expect(throws: ArtifactError(
        "SwiftSyntax 604.0.0 does not match Swift 6.3."
      )) {
        try ArtifactConfiguration.load(from: url)
      }
    }
  }

  private func loadConfiguration(in directory: URL) throws
    -> ArtifactConfiguration
  {
    let url = directory.appendingPathComponent("configuration.json")
    try configurationJSON().write(
      to: url,
      atomically: true,
      encoding: .utf8
    )
    return try ArtifactConfiguration.load(from: url)
  }
}

private func configurationJSON(compilerVersion: String = "6.4") -> String {
  """
  {
    "mode": "source",
    "swiftCompilerVersion": "\(compilerVersion)",
    "swiftSyntaxVersion": "604.0.0",
    "sourceRevision": "050f1a346fbbac0ca2cfb15a95274f7bd1cf0ccf",
    "artifactRevision": 1
  }
  """
}
