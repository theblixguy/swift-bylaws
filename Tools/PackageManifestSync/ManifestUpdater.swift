import BylawsSyntax

enum ManifestUpdater {
  private static let pluginFields: Set<String> = ["url", "checksum"]
  private static let configurationFields: Set<String> = [
    "mode", "swiftCompilerVersion", "swiftSyntaxVersion",
    "artifactRevision", "swiftArtifactChecksum", "cArtifactChecksum",
  ]

  static func updatedSource(
    _ source: String,
    metadata: ManifestMetadata,
    pluginArtifact: PluginToolArtifact? = nil
  ) throws -> String {
    let names = metadata.swiftSyntax.map(\.name)
    guard Set(names).count == names.count else {
      throw ManifestError.compilerVersionsDiffer
    }
    for (name, configuration) in metadata.swiftSyntax
      where configuration.mode == .remote
    {
      guard configuration.swiftArtifactChecksum != nil,
            configuration.cArtifactChecksum != nil
      else {
        throw ManifestError.missingSwiftSyntaxChecksums(name)
      }
    }

    let configurations = Dictionary(
      uniqueKeysWithValues: metadata.swiftSyntax.map { ($0.name, $0.metadata) }
    )
    let rewriter = ManifestValueRewriter(
      pluginArtifact: pluginArtifact,
      configurations: configurations
    )
    let updated = rewriter.rewrite(Parser.parse(source: source))

    if pluginArtifact != nil {
      guard rewriter.pluginEnumCount == 1 else {
        throw ManifestError.missingDeclaration("PluginToolArtifact")
      }
      for field in pluginFields where rewriter.pluginUpdates[field] != 1 {
        throw ManifestError.missingDeclaration("PluginToolArtifact.\(field)")
      }
    }
    guard rewriter.swiftVersionEnumCount == 1 else {
      throw ManifestError.missingDeclaration("SwiftSyntaxArtifact.SwiftVersion")
    }
    guard rewriter.compilerVersions == Set(names) else {
      throw ManifestError.compilerVersionsDiffer
    }
    for name in names {
      for field in configurationFields
        where rewriter.configurationUpdates[name]?[field] != 1
      {
        throw ManifestError.missingDeclaration("\(name).\(field)")
      }
    }
    return updated.description
  }
}
