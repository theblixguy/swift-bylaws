import BylawsCore
import BylawsPaths
import BylawsSemantics
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
    let parsedRoot: ParsedRulesFile?
    let diagnostics: [Diagnostic]
  }

  static func rulesFiles(
    underRoot rootPath: String,
    overlay: SourceOverlay
  ) async -> Discovery {
    await files(named: fileName, underRoot: rootPath, overlay: overlay)
  }

  static func baselineFiles(
    underRoot rootPath: String,
    overlay: SourceOverlay
  ) async -> Discovery {
    await files(named: baselineFileName, underRoot: rootPath, overlay: overlay)
  }

  private static let manifestName = "Package.swift"

  private static let skippedDirectories: Set<String> = [
    ".git", ".build", ".swiftpm", "DerivedData", "node_modules", "Pods",
  ]

  private static func files(
    named name: String,
    underRoot rootPath: String,
    overlay: SourceOverlay
  ) async -> Discovery {
    let manager = FileManager.default
    var files: [DiscoveredFile] = []

    let root = LexicalFilePath(rootPath)
    let rootRulesPath = root.appending(fileName).string
    let parsedRoot: ParsedRulesFile? =
      if overlay.text(forFileAt: rootRulesPath) != nil
        || manager.fileExists(atPath: rootRulesPath)
      {
        .loaded(at: rootRulesPath, overlay: overlay)
      } else {
        nil
      }
    let rootFile = root.appending(name).string
    if manager.fileExists(atPath: rootFile)
      || (name == fileName && overlay.text(forFileAt: rootFile) != nil)
    {
      files.append(DiscoveredFile(path: rootFile, relativeDirectory: ""))
    }

    let walk = await moduleDirectories(
      underRoot: rootPath,
      excluding: parsedRoot?.discovery?.value?.excludedFolders ?? []
    )
    for directory in walk.directories {
      let path = root.appending(directory).appending(name).string
      if manager.fileExists(atPath: path) {
        files.append(DiscoveredFile(path: path, relativeDirectory: directory))
      }
    }
    return Discovery(
      files: files,
      parsedRoot: parsedRoot,
      diagnostics: walk.unopenableDirectories.map { path in
        .error(
          "cannot read the directory",
          at: .start(of: path),
          hint: "check the directory's permissions"
        )
      }
    )
  }

  private static func moduleDirectories(
    underRoot rootPath: String,
    excluding folders: [Glob]
  ) async -> (directories: [String], unopenableDirectories: [String]) {
    var directories: [String] = []
    let unopenable = await DirectoryWalker
      .walk(rootPath) { relativePath, entry in
        let path = LexicalFilePath(relativePath)
        switch entry {
        case .directory:
          let skipped = path.lastComponent.map(skippedDirectories.contains)
          if skipped == true { return .skipDescendants }
          if folders.isEmpty { return .descend }
          let folder = Glob.Path(relativePath)
          return folders.contains { $0.matches(folder) }
            ? .skipDescendants : .descend
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
