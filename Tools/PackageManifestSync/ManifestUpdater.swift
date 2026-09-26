import BylawsSyntax

enum ManifestUpdater {
  private static let pluginFields: Set<String> = ["mode", "url", "checksum"]
  private static let configurationFields: Set<String> = [
    "mode", "swiftCompilerVersion", "swiftSyntaxVersion",
    "artifactRevision", "swiftArtifactChecksum", "cArtifactChecksum",
  ]

  static func updatedSource(
    _ source: String,
    metadata: ManifestMetadata
  ) throws -> String {
    if metadata.pluginTool.mode == .remote {
      guard metadata.pluginTool.url != nil,
            metadata.pluginTool.checksum != nil
      else {
        throw ManifestError.missingPluginToolArtifact
      }
    }

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
      pluginTool: metadata.pluginTool,
      configurations: configurations
    )
    let updated = rewriter.rewrite(Parser.parse(source: source))

    guard rewriter.pluginEnumCount == 1 else {
      throw ManifestError.missingDeclaration("PluginToolArtifact")
    }
    guard rewriter.swiftVersionEnumCount == 1 else {
      throw ManifestError.missingDeclaration("SwiftSyntaxArtifact.SwiftVersion")
    }
    for field in pluginFields where rewriter.pluginUpdates[field] != 1 {
      throw ManifestError.missingDeclaration("PluginToolArtifact.\(field)")
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
