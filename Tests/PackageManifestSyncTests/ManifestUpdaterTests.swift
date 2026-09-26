import Testing
@testable import PackageManifestSync

@Suite("Package manifest updates")
struct ManifestUpdaterTests {
  private let metadata = ManifestMetadata(
    swiftSyntax: [
      (
        name: "v6_3",
        metadata: SwiftSyntaxMetadata(
          mode: .source,
          swiftCompilerVersion: "6.3.3",
          swiftSyntaxVersion: "603.0.2",
          artifactRevision: 2,
          swiftArtifactChecksum: nil,
          cArtifactChecksum: nil
        )
      ),
    ]
  )

  private let source = """
  private enum PluginToolArtifact {
    static let url = "old"
    static let checksum = "old"
  }

  private enum SwiftSyntaxArtifact {
    enum SwiftVersion {
      case v6_3

      var configuration: SwiftSyntaxArtifactConfiguration {
        switch self {
        case .v6_3:
          SwiftSyntaxArtifactConfiguration(
            mode: .remote,
            swiftCompilerVersion: "old",
            swiftSyntaxVersion: "old",
            artifactRevision: 1,
            swiftArtifactChecksum: "old",
            cArtifactChecksum: "old"
          )
        }
      }
    }
  }

  private enum Elsewhere {
    enum SwiftVersion {
      case unchanged
    }
  }

  let text = "PluginToolArtifact SwiftVersion"
  """

  @Test("SwiftSyntax declarations update without changing plugin artifact")
  func updatesNamedDeclarations() throws {
    let updated = try ManifestUpdater.updatedSource(source, metadata: metadata)
    let repeated = try ManifestUpdater.updatedSource(
      updated,
      metadata: metadata
    )

    #expect(updated.contains("static let url = \"old\""))
    #expect(updated.contains("static let checksum = \"old\""))
    #expect(updated.contains("swiftCompilerVersion: \"6.3.3\""))
    #expect(updated.contains("artifactRevision: 2"))
    #expect(updated.contains("case unchanged"))
    #expect(updated.contains("let text = \"PluginToolArtifact SwiftVersion\""))
    #expect(updated == repeated)
  }

  @Test("Missing declaration stops update")
  func missingDeclaration() {
    let source = "private enum PluginToolArtifact {}"

    #expect(throws: ManifestError.self) {
      _ = try ManifestUpdater.updatedSource(
        source,
        metadata: metadata,
        pluginArtifact: PluginToolArtifact(url: "new", checksum: "abc")
      )
    }
  }

  @Test("Duplicate declaration stops update")
  func duplicateDeclaration() {
    let source = source + "\nprivate enum PluginToolArtifact {}"

    #expect(throws: ManifestError.self) {
      _ = try ManifestUpdater.updatedSource(
        source,
        metadata: metadata,
        pluginArtifact: PluginToolArtifact(url: "new", checksum: "abc")
      )
    }
  }

  @Test("Unknown compiler version stops update")
  func unknownCompilerVersion() {
    let metadata = ManifestMetadata(
      swiftSyntax: [(name: "v6_4", metadata: metadata.swiftSyntax[0].metadata)]
    )

    #expect(throws: ManifestError.self) {
      _ = try ManifestUpdater.updatedSource(source, metadata: metadata)
    }
  }

  @Test("String values retain Swift escaping")
  func escapesStringValues() throws {
    let updated = try ManifestUpdater.updatedSource(
      source,
      metadata: metadata,
      pluginArtifact: PluginToolArtifact(url: "a\"b\\c", checksum: "abc")
    )

    #expect(updated.contains("static let url = \"a\\\"b\\\\c\""))
    #expect(updated.contains("static let checksum = \"abc\""))
  }
}
