import BylawsPaths
import BylawsSemantics

extension Codebase {
  /// Returns one group for each matching folder that contains selected sources.
  ///
  /// The pattern uses root-relative glob syntax. Results are sorted by their
  /// root-relative folder paths, which are also their names. Each group
  /// selects all sources below its folder. Empty folders are not included.
  /// This query does not read a compiler index or check for overlapping groups.
  ///
  /// - Throws: ``DependencyGroupError`` for an unsupported pattern, unreadable
  ///   sources or a matching folder path with glob characters or backslashes.
  public func dependencyGroups(
    inFoldersMatching pattern: String
  ) async throws(DependencyGroupError) -> [DependencyGroup] {
    try DependencyGroup.validate(pattern: pattern)
    let parsed: ParsedCodebase
    do {
      parsed = try await CodebaseCache.shared.parsedCodebase(for: self)
    } catch {
      throw .unreadableCodebase(error)
    }
    let root = LexicalFilePath(parsed.rootPath)
    let glob = Glob(pattern)
    var folders: Set<String> = []
    for file in parsed.filesAsWritten {
      guard let relative = LexicalFilePath(file.path).relative(to: root)
      else { continue }
      var parent = relative.removingLastComponent()
      while !parent.string.isEmpty {
        if glob.matches(parent.string) { folders.insert(parent.string) }
        parent = parent.removingLastComponent()
      }
    }
    return try folders.sorted().map { folder throws(DependencyGroupError) in
      guard !folder.contains(where: { "*?\\".contains($0) }) else {
        throw .unsupportedFolderPath(folder)
      }
      return DependencyGroup(folder, files: [folder + "/**"])
    }
  }
}
