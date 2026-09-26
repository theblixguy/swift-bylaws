import Foundation

do {
  let arguments = Array(CommandLine.arguments.dropFirst())
  guard arguments.isEmpty || arguments == ["--check"] else {
    throw ManifestError.usage
  }

  let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  let metadata = try ManifestMetadata(root: root)
  let manifestURL = root.appendingPathComponent("Package.swift")
  let current = try String(contentsOf: manifestURL, encoding: .utf8)
  let updated = try ManifestUpdater.updatedSource(current, metadata: metadata)
  if arguments == ["--check"] {
    guard current == updated else { throw ManifestError.outOfSync }
  } else if current != updated {
    try updated.write(to: manifestURL, atomically: true, encoding: .utf8)
  }
} catch {
  FileHandle.standardError.write(Data("\(error)\n".utf8))
  exit(1)
}
