import BylawsCore
import BylawsPaths
import Foundation

enum RulesDiscovery {
  static let fileName = "Bylaws.swift"
  static let baselineFileName = "Bylaws.baseline.swift"

  struct DiscoveredFile {
    let path: String
    let relativeDirectory: String

    var isRoot: Bool { relativeDirectory.isEmpty }
  }

  struct Discovery {
    let files: [DiscoveredFile]
    let unopenableDirectories: [String]
  }

  static func rulesFiles(underRoot rootPath: String) async -> Discovery {
    await files(named: fileName, underRoot: rootPath)
  }

  static func baselineFiles(underRoot rootPath: String) async -> Discovery {
    await files(named: baselineFileName, underRoot: rootPath)
  }

  private static let manifestName = "Package.swift"

  private static let skippedDirectories: Set<String> = [
    ".git", ".build", ".swiftpm", "DerivedData", "node_modules", "Pods",
  ]

  private static func files(
    named name: String,
    underRoot rootPath: String
  ) async -> Discovery {
    let manager = FileManager.default
    var files: [DiscoveredFile] = []

    let root = LexicalFilePath(rootPath)
    let rootFile = root.appending(name).string
    if manager.fileExists(atPath: rootFile) {
      files.append(DiscoveredFile(path: rootFile, relativeDirectory: ""))
    }

    let walk = await moduleDirectories(underRoot: rootPath)
    for directory in walk.directories {
      let path = root.appending(directory).appending(name).string
      if manager.fileExists(atPath: path) {
        files.append(DiscoveredFile(path: path, relativeDirectory: directory))
      }
    }
    return Discovery(
      files: files,
      unopenableDirectories: walk.unopenableDirectories
    )
  }

  private static func moduleDirectories(
    underRoot rootPath: String
  ) async -> (directories: [String], unopenableDirectories: [String]) {
    var directories: [String] = []
    let unopenable = await DirectoryWalker
      .walk(rootPath) { relativePath, entry in
        let path = LexicalFilePath(relativePath)
        switch entry {
        case .directory:
          let skipped = path.lastComponent.map(skippedDirectories.contains)
          return skipped == true ? .skipDescendants : .descend
        case .regularFile:
          if path.lastComponent == manifestName {
            let directory = path.removingLastComponent().string
            if !directory.isEmpty { directories.append(directory) }
          }
          return .descend
        }
      }
    return (
      directories.sorted(),
      unopenable.map { directory in
        directory.relativePath.isEmpty
          ? rootPath : "\(rootPath)/\(directory.relativePath)"
      }
    )
  }
}
