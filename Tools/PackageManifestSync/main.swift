import Foundation

do {
  let arguments = Array(CommandLine.arguments.dropFirst())
  let check = arguments.first == "--check"
  let values = check ? Array(arguments.dropFirst()) : arguments
  let pluginArtifact: PluginToolArtifact?
  switch values {
  case []:
    pluginArtifact = nil
  case let values where values.count == 3
    && values[0] == "--plugin-artifact":
    pluginArtifact = PluginToolArtifact(
      url: values[1],
      checksum: values[2]
    )
  default:
    throw ManifestError.usage
  }

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
} catch {
  FileHandle.standardError.write(Data("\(error)\n".utf8))
  exit(1)
}
