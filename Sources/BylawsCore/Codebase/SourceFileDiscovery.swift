import BylawsPaths

enum SourceFileDiscovery {
  static func paths(
    under rootPath: String, including: [Glob], excluding: [Glob]
  ) async -> (paths: [String], failures: [CodebaseError.ReadFailure]) {
    let root = LexicalFilePath(rootPath)
    var paths: [String] = []
    let failures = await DirectoryWalker.walk(rootPath) { relative, entry in
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
        paths.append(root.appending(relative).string)
        return .descend
      }
    }
    return (
      paths,
      failures.map { failure in
        CodebaseError.ReadFailure(
          path: root.appending(failure.relativePath).string,
          reason: failure.reason
        )
      }.sorted { $0.path < $1.path }
    )
  }
}
