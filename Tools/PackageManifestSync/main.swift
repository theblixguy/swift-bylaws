import ArgumentParser
import Foundation

struct PackageManifestSync: ParsableCommand {
  @Flag(help: "Check Package.swift without changing it.")
  var check = false

  @Option(help: "Use this URL for the plugin artifact.")
  var pluginURL: String?

  @Option(help: "Use this checksum for the plugin artifact.")
  var pluginChecksum: String?

  private var pluginArtifact: PluginToolArtifact? {
    guard let pluginURL, let pluginChecksum else { return nil }
    return PluginToolArtifact(url: pluginURL, checksum: pluginChecksum)
  }

  mutating func validate() throws {
    guard (pluginURL == nil) == (pluginChecksum == nil) else {
      throw ValidationError(
        "Pass --plugin-url and --plugin-checksum together."
      )
    }
  }

  func run() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let metadata = try ManifestMetadata(root: root)
    let manifestURL = root.appendingPathComponent("Package.swift")
    let current = try String(contentsOf: manifestURL, encoding: .utf8)
    let updated = try ManifestUpdater.updatedSource(
      current,
      metadata: metadata,
      pluginArtifact: pluginArtifact
    )
    if check {
      guard current == updated else { throw ManifestError.outOfSync }
    } else if current != updated {
      try updated.write(to: manifestURL, atomically: true, encoding: .utf8)
    }
  }
}

PackageManifestSync.main()
