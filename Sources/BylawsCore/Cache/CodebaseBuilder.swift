import BylawsPaths
import BylawsSemantics
import Foundation

enum CodebaseBuilder {
  private static let maximumConcurrentFileTasks = max(
    1,
    ProcessInfo.processInfo.activeProcessorCount
  )

  struct Build: Sendable {
    let parsed: ParsedCodebase
    let rawFilesByPath: [String: SourceFile]
  }

  struct ReusableFiles: Sendable {
    let overlay: SourceOverlay
    let filesByPath: [String: SourceFile]

    func file(at path: String, for overlay: SourceOverlay) -> SourceFile? {
      guard self.overlay.text(forFileAt: path) == overlay.text(forFileAt: path)
      else { return nil }
      return filesByPath[path]
    }
  }

  static func build(
    _ codebase: Codebase,
    reusing reusable: ReusableFiles?
  ) async throws(CodebaseError) -> Build {
    if case let .sources(sources) = codebase.root.strategy {
      let files = try sourceFiles(of: sources, in: codebase)
      return Build(
        parsed: ParsedCodebase(
          rootPath: Codebase.sourcesRootPath,
          files: files
        ),
        rawFilesByPath: Dictionary(
          files.map { ($0.path, $0) },
          uniquingKeysWith: { _, latest in latest }
        )
      )
    }
    let rootPath = try codebase.resolvedRootPath()
    let (diskPaths, unopenableDirectories) = await swiftFilePaths(
      under: rootPath,
      in: codebase
    )
    let paths = merging(
      diskPaths,
      withOverlaidPathsUnder: rootPath,
      in: codebase
    )
    let parseCache = parseCache(
      forRoot: rootPath,
      policy: codebase.parseCachePolicy
    )
    var filesByPath: [String: SourceFile] = [:]
    var readFailures = unopenableDirectories
    var unparsedPaths: [String] = []

    let results = await boundedConcurrentMap(
      paths,
      maximumConcurrentTasks: maximumConcurrentFileTasks
    ) { path in
      Result { () throws(ParseError) in
        try collect(
          path,
          from: codebase.overlay,
          reusing: reusable,
          through: parseCache
        )
      }
    }
    for result in results {
      switch result {
      case let .success(file): filesByPath[file.path] = file
      case let .failure(.unreadable(path, reason)):
        readFailures.append(.init(path: path, reason: reason))
      case let .failure(.didNotParse(path)): unparsedPaths.append(path)
      }
    }
    parseCache?.removeOldEntriesWhenDue()

    guard readFailures.isEmpty else {
      throw CodebaseError.unreadable(
        failures: readFailures.sorted { $0.path < $1.path }
      )
    }

    guard unparsedPaths.isEmpty else {
      throw CodebaseError.didNotParse(paths: unparsedPaths.sorted())
    }

    let files = paths.compactMap { filesByPath[$0] }
    return Build(
      parsed: ParsedCodebase(rootPath: rootPath, files: files),
      rawFilesByPath: filesByPath
    )
  }

  static func packageAnalysis(
    of parsedCodebase: ParsedCodebase,
    from overlay: SourceOverlay
  ) throws(CodebaseError) -> PackageAnalysis {
    let root = LexicalFilePath(parsedCodebase.rootPath)
    let manifestPath = root.appending("Package.swift").string
    let manifestFile: SourceFile
    do {
      manifestFile = try collect(
        manifestPath,
        from: overlay,
        reusing: nil,
        through: nil
      )
    } catch {
      switch error {
      case let .unreadable(path, reason):
        throw CodebaseError.unreadable(
          failures: [.init(path: path, reason: reason)]
        )
      case let .didNotParse(path):
        throw CodebaseError.didNotParse(paths: [path])
      }
    }
    return PackageAnalysis(
      parsedCodebase: parsedCodebase,
      manifestSource: manifestFile.sourceText
    )
  }

  private static func sourceFiles(
    of sources: [String: String],
    in codebase: Codebase
  ) throws(CodebaseError) -> [SourceFile] {
    var files: [SourceFile] = []
    var unparsedPaths: [String] = []
    for (path, source) in sources.sorted(by: { $0.key < $1.key }) {
      guard codebase.covers(Glob.Path(path)) else { continue }

      let rootRelativePath = path.drop { $0 == "/" }
      let fullPath = LexicalFilePath(Codebase.sourcesRootPath)
        .appending(String(rootRelativePath)).string
      do {
        files.append(
          try FileCollector.collect(
            source: source,
            path: fullPath
          )
        )
      } catch {
        unparsedPaths.append(fullPath)
      }
    }
    guard unparsedPaths.isEmpty else {
      throw CodebaseError.didNotParse(paths: unparsedPaths)
    }
    return files
  }

  private static func parseCache(
    forRoot rootPath: String,
    policy: ParseCachePolicy
  ) -> ParseCache? {
    guard case let .enabled(directory, cachesTemporaryRoots) = policy else {
      return nil
    }
    let temporaryDirectories = [
      FileManager.default.temporaryDirectory.path,
      "/tmp", "/private/tmp", "/var/folders", "/private/var/folders",
    ]
    guard cachesTemporaryRoots
      || !temporaryDirectories.contains(where: {
        contains(rootPath, in: $0)
      })
    else {
      return nil
    }
    guard let name = LexicalFilePath(rootPath).lastComponent else { return nil }
    return try? ParseCache.opening(directory: directory)
      .opening(project: String(name))
  }

  static func contains(_ path: String, in directory: String) -> Bool {
    LexicalFilePath(directory).contains(LexicalFilePath(path))
  }

  private static func collect(
    _ path: String,
    from overlay: SourceOverlay,
    reusing reusable: ReusableFiles?,
    through parseCache: ParseCache?
  ) throws(ParseError) -> SourceFile {
    if let reused = reusable?.file(at: path, for: overlay) { return reused }
    // Caching unsaved text would create disk entries for temporary edits.
    if let overlaid = overlay.text(forFileAt: path) {
      return try FileCollector.collect(source: overlaid, path: path)
    }
    let source = try FileCollector.readSource(atPath: path)
    if let cached = parseCache?.sourceFile(forSource: source, at: path) {
      return cached
    }
    let file = try FileCollector.collect(source: source, path: path)
    parseCache?.store(file, forSource: source, at: path)
    return file
  }

  private static func merging(
    _ diskPaths: [String],
    withOverlaidPathsUnder rootPath: String,
    in codebase: Codebase
  ) -> [String] {
    guard !codebase.overlay.isEmpty else { return diskPaths.sorted() }
    let root = LexicalFilePath(rootPath)
    let savedPaths = Set(diskPaths)
    let overlaid = codebase.overlay.paths.filter { path in
      guard !savedPaths.contains(path), path.hasSuffix(".swift"),
            let relativePath = LexicalFilePath(path).relative(to: root)?.string
      else { return false }
      return codebase.covers(Glob.Path(relativePath))
    }
    return (diskPaths + overlaid).sorted()
  }

  private static func swiftFilePaths(
    under rootPath: String,
    in codebase: Codebase
  ) async -> (
    paths: [String],
    unopenableDirectories: [CodebaseError.ReadFailure]
  ) {
    let root = LexicalFilePath(rootPath)
    var paths: [String] = []
    let unopenable = await DirectoryWalker
      .walk(rootPath) { relativePath, entry in
        switch entry {
        case .directory:
          let directory = Glob.Path(relativePath)
          let covered = codebase.excluding.contains {
            $0.coversEverything(under: directory)
          }
          let reachable = codebase.including.isEmpty
            || codebase.including.contains {
              $0.canMatchDescendant(of: directory)
            }
          return covered || !reachable ? .skipDescendants : .descend
        case .regularFile:
          guard relativePath.hasSuffix(".swift") else { return .descend }
          if codebase.covers(Glob.Path(relativePath)) {
            paths.append(root.appending(relativePath).string)
          }
          return .descend
        }
      }
    return (
      paths,
      unopenable.map { directory in
        CodebaseError.ReadFailure(
          path: directory.relativePath.isEmpty
            ? rootPath : root.appending(directory.relativePath).string,
          reason: directory.reason
        )
      }
    )
  }
}

extension Codebase {
  fileprivate func covers(_ path: Glob.Path) -> Bool {
    let included = including.isEmpty || including.contains { $0.matches(path) }
    return included && !excluding.contains { $0.matches(path) }
  }
}
