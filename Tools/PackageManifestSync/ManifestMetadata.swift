import Foundation

enum ArtifactMode: String, Decodable {
  case remote
  case source
}

struct PluginToolMetadata: Decodable {
  let mode: ArtifactMode
  let url: String?
  let checksum: String?
}

struct SwiftSyntaxMetadata: Decodable {
  let mode: ArtifactMode
  let swiftCompilerVersion: String
  let swiftSyntaxVersion: String
  let artifactRevision: Int
  let swiftArtifactChecksum: String?
  let cArtifactChecksum: String?
}

struct ManifestMetadata {
  let pluginTool: PluginToolMetadata
  let swiftSyntax: [(name: String, metadata: SwiftSyntaxMetadata)]

  init(
    pluginTool: PluginToolMetadata,
    swiftSyntax: [(name: String, metadata: SwiftSyntaxMetadata)]
  ) {
    self.pluginTool = pluginTool
    self.swiftSyntax = swiftSyntax
  }

  init(root: URL) throws {
    let decoder = JSONDecoder()
    let pluginURL = root.appendingPathComponent("Distribution/PluginTool.json")
    pluginTool = try decoder.decode(
      PluginToolMetadata.self,
      from: Data(contentsOf: pluginURL)
    )

    let syntaxDirectory = root
      .appendingPathComponent("Distribution/SwiftSyntax")
    let files = try FileManager.default.contentsOfDirectory(
      at: syntaxDirectory,
      includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "json" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }

    swiftSyntax = try files.map { file in
      let metadata = try decoder.decode(
        SwiftSyntaxMetadata.self,
        from: Data(contentsOf: file)
      )
      let parts = metadata.swiftCompilerVersion.split(separator: ".")
      guard parts.count >= 2,
            let major = Int(parts[0]),
            let minor = Int(parts[1])
      else {
        throw ManifestError.invalidVersion(file.lastPathComponent)
      }
      return (name: "v\(major)_\(minor)", metadata: metadata)
    }
  }
}

enum ManifestError: Error, CustomStringConvertible {
  case missingDeclaration(String)
  case missingPluginToolArtifact
  case missingSwiftSyntaxChecksums(String)
  case invalidVersion(String)
  case compilerVersionsDiffer
  case outOfSync
  case usage

  var description: String {
    switch self {
    case let .missingDeclaration(name):
      "Package.swift must have one \(name) declaration."
    case .missingPluginToolArtifact:
      "PluginTool.json must have a URL and checksum in remote mode."
    case let .missingSwiftSyntaxChecksums(name):
      "\(name) must have both artifact checksums in remote mode."
    case let .invalidVersion(name):
      "\(name) must name a Swift compiler version such as 6.3.3."
    case .compilerVersionsDiffer:
      "Package.swift and Distribution/SwiftSyntax must name the same Swift compiler versions. Update both files."
    case .outOfSync:
      "Package.swift differs from Distribution metadata. Run swift run PackageManifestSync."
    case .usage:
      "Use swift run PackageManifestSync [--check]."
    }
  }
}
