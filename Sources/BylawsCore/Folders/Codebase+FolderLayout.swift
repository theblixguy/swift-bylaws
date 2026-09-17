import BylawsPaths

extension Codebase {
  /// Checks that each matching folder contains exactly the named child folders.
  ///
  /// The pattern is relative to the codebase root and uses ``Glob`` syntax.
  /// Use `"."` to check the root itself. Child names are literal single path
  /// components. An empty list permits no child folders.
  ///
  /// Each call checks the current directories, including empty folders and
  /// folders that contain only resources. The check ignores regular files,
  /// symbolic links and the codebase's source include and exclude globs.
  /// For inline sources, it infers folders from the supplied file paths.
  ///
  /// - Throws: ``FolderLayoutError`` for unsupported paths or an unreadable
  ///   root or directory.
  public func checkFolderLayout(
    matching pattern: String,
    containing folders: [String]
  ) async throws(FolderLayoutError) -> FolderLayoutCheck {
    try Self.validateFolderLayout(pattern: pattern, folders: folders)
    let glob = Glob(pattern == "." ? "" : pattern)
    let rootPath: String
    let directories: Set<String>
    do {
      rootPath = try resolvedRootPath()
      await recordDescendantsDependency(rootPath)
      directories = try await layoutDirectories(
        matching: glob,
        rootPath: rootPath
      )
    } catch {
      throw .unreadableCodebase(error)
    }
    let matched = directories.filter(glob.matches).sorted()
    let required = Set(folders)
    var children: [String: Set<String>] = [:]
    for directory in directories where !directory.isEmpty {
      let path = LexicalFilePath(directory)
      guard let name = path.lastComponent else { continue }
      children[path.removingLastComponent().string, default: []].insert(name)
    }
    var missing: [String] = []
    var unexpected: [String] = []
    for directory in matched {
      let actual = children[directory, default: []]
      let path = LexicalFilePath(directory)
      missing += required.subtracting(actual).map { path.appending($0).string }
      unexpected += actual.subtracting(required)
        .map { path.appending($0).string }
    }
    return FolderLayoutCheck(
      matchedFolders: matched.map { $0.isEmpty ? "." : $0 },
      missingFolders: missing.sorted(),
      unexpectedFolders: unexpected.sorted(),
      pattern: pattern,
      rootPath: rootPath
    )
  }

  private static func validateFolderLayout(
    pattern: String,
    folders: [String]
  ) throws(FolderLayoutError) {
    let components = pattern.split(separator: "/")
    guard !pattern.isEmpty, !pattern.hasPrefix("/"),
          !pattern.contains("\\"), !pattern.contains("\0"),
          !components.contains(".."),
          pattern == "." || !components.contains(".")
    else { throw .unsupportedPattern(pattern) }
    for name in folders {
      guard !name.isEmpty, name != ".", name != "..",
            !name.contains(where: { "/\\*?\0".contains($0) })
      else { throw .unsupportedFolderName(name) }
    }
  }

  private func layoutDirectories(
    matching glob: Glob,
    rootPath: String
  ) async throws(CodebaseError) -> Set<String> {
    var directories: Set = [""]
    switch root.strategy {
    case let .sources(files):
      let root = LexicalFilePath(Self.sourcesRootPath)
      for file in files.keys {
        guard let path = root.resolvingDescendant(file)?.relative(to: root)
        else {
          continue
        }
        var parent = path.removingLastComponent()
        while !parent.string.isEmpty {
          directories.insert(parent.string)
          parent = parent.removingLastComponent()
        }
      }
    case .directory, .automatic:
      if case let .prepared(sources) = sourceLoading {
        directories.formUnion(
          sources.relativeDirectories(under: rootPath)
        )
        return directories
      }
      let failures = await DirectoryWalker.walk(rootPath) { path, entry in
        guard entry == .directory else { return .skipDescendants }
        directories.insert(path)
        return glob.matches(path) || glob
          .canMatchDescendant(of: Glob.Path(path))
          ? .descend : .skipDescendants
      }
      guard failures.isEmpty else {
        throw .unreadable(failures: failures.map { failure in
          .init(
            path: LexicalFilePath(rootPath).appending(failure.relativePath)
              .string,
            reason: failure.reason
          )
        }.sorted { $0.path < $1.path })
      }
    }
    return directories
  }
}
