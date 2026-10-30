import BylawsPaths
import SystemPackage

enum SourceFileDiscovery {
  static func paths(
    under rootPath: String, including: [Glob], excluding: [Glob],
    collectParentDirectories: Bool = false
  ) async -> (
    paths: [String], relativeParentDirectories: [LexicalFilePath],
    failures: [CodebaseError.ReadFailure]
  ) {
    let root = LexicalFilePath(rootPath).string
    let prefix = root.hasSuffix("/") ? root : root + "/"
    var paths: [String] = []
    var parents: [LexicalFilePath] = []
    var seenParents: Set<FilePath> = []
    let failures = await DirectoryWalker.walk(root) { relative, parent, entry in
      let path = Glob.Path(relative)
      switch entry {
      case .directory:
        let excluded = excluding.contains { $0.coversEverything(under: path) }
        let reachable = including.isEmpty
          || including.contains { $0.canMatchDescendant(of: path) }
        return excluded || !reachable ? .skipDescendants : .descend
      case .regularFile:
        guard relative.hasSuffix(".swift"),
              including.isEmpty || including
                .contains(where: { $0.matches(path) }),
              !excluding.contains(where: { $0.matches(path) })
        else { return .descend }
        paths.append(prefix + relative)
        if collectParentDirectories, seenParents.insert(parent).inserted {
          parents.append(LexicalFilePath(parent.string))
        }
        return .descend
      }
    }
    return (
      paths,
      parents,
      failures.map { failure in
        CodebaseError.ReadFailure(
          path: failure.relativePath.isEmpty ? root : prefix + failure
            .relativePath,
          reason: failure.reason
        )
      }.sorted { $0.path < $1.path }
    )
  }
}
