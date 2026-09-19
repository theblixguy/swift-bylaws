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

    func file(
      at path: String, for overlay: SourceOverlay,
      swiftLanguageMode: SwiftLanguageMode
    ) -> SourceFile? {
      guard self.overlay.text(forFileAt: path) == overlay.text(forFileAt: path),
            filesByPath[path]?.swiftLanguageMode == swiftLanguageMode
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
    if case let .prepared(prepared) = codebase.sourceLoading {
      let files = prepared.files.filter { file in
        guard contains(file.path, in: rootPath),
              let relativePath = LexicalFilePath(file.path)
              .relative(to: LexicalFilePath(rootPath))?.string
        else { return false }
        return codebase.covers(Glob.Path(relativePath))
      }
      return Build(
        parsed: ParsedCodebase(rootPath: rootPath, files: files),
        rawFilesByPath: Dictionary(
          uniqueKeysWithValues: files.map { ($0.path, $0) }
        )
      )
    }
    let (diskPaths, unopenableDirectories) = await swiftFilePaths(
      under: rootPath,
      in: codebase
    )
    let paths = merging(
      diskPaths,
      withOverlaidPathsUnder: rootPath,
      in: codebase
    )
    let parseCache = ParseCache.opening(
      forRoot: rootPath,
      policy: codebase.parseCachePolicy
    )
    var filesByPath: [String: SourceFile] = [:]
    var readFailures = unopenableDirectories
    var parseDiagnostics: [SourceParseDiagnostic] = []

    var settings = SourceLanguageModes(
      root: rootPath,
      overlay: codebase.overlay,
      languageMode: codebase.swiftLanguageMode
    )
    var inputs: [(path: String, mode: SwiftLanguageMode)] = []
    for path in paths {
      let mode = try settings.mode(for: path)
      inputs.append((path, mode))
    }

    let results = await boundedConcurrentMap(
      inputs,
      maximumConcurrentTasks: maximumConcurrentFileTasks
    ) { input in
      await Result(catching: { () async throws(ParseError) in
        try await collect(
          input.path,
          from: codebase.overlay,
          reusing: reusable,
          through: parseCache,
          swiftLanguageMode: input.mode
        )
      })
    }
    for result in results {
      switch result {
      case let .success(file): filesByPath[file.path] = file
      case let .failure(.unreadable(path, reason)):
        readFailures.append(.init(path: path, reason: reason))
      case let .failure(.didNotParse(diagnostics)): parseDiagnostics +=
        diagnostics
      }
    }
    await parseCache?.removeOldEntriesWhenDue()

    guard readFailures.isEmpty else {
      throw CodebaseError.unreadable(
        failures: readFailures.sorted { $0.path < $1.path }
      )
    }

    guard parseDiagnostics.isEmpty else {
      throw CodebaseError.didNotParse(diagnostics: parseDiagnostics.sorted {
        ($0.location.filePath, $0.location.line, $0.location.column)
          < ($1.location.filePath, $1.location.line, $1.location.column)
      })
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
    let manifest: PackageManifest
    do {
      let source = if let overlaid = overlay
        .text(forFileAt: manifestPath) { overlaid }
      else { try FileCollector.readSource(atPath: manifestPath) }
      manifest = PackageManifest(source: source)
      let mode = SwiftLanguageMode(toolsVersion: manifest.toolsVersion)
      _ = try FileCollector.collect(
        source: source, path: manifestPath,
        swiftLanguageMode: mode
      )
    } catch {
      switch error {
      case let .unreadable(path, reason):
        throw CodebaseError.unreadable(
          failures: [.init(path: path, reason: reason)]
        )
      case let .didNotParse(diagnostics):
        throw CodebaseError.didNotParse(diagnostics: diagnostics)
      }
    }
    return PackageAnalysis(
      parsedCodebase: parsedCodebase,
      manifest: manifest
    )
  }

  private static func sourceFiles(
    of sources: [String: String],
    in codebase: Codebase
  ) throws(CodebaseError) -> [SourceFile] {
    var files: [SourceFile] = []
    var parseDiagnostics: [SourceParseDiagnostic] = []
    let root = LexicalFilePath(Codebase.sourcesRootPath)
    let absoluteSources = Dictionary(
      sources.map { (
        root.appending(String($0.key.drop { $0 == "/" })).string,
        $0.value
      ) },
      uniquingKeysWith: { _, latest in latest }
    )
    var settings = SourceLanguageModes(
      root: root.string,
      sources: absoluteSources,
      languageMode: codebase.swiftLanguageMode
    )
    for (path, source) in sources.sorted(by: { $0.key < $1.key }) {
      guard codebase.covers(Glob.Path(path)) else { continue }

      let rootRelativePath = path.drop { $0 == "/" }
      let fullPath = LexicalFilePath(Codebase.sourcesRootPath)
        .appending(String(rootRelativePath)).string
      let mode = try settings.mode(for: fullPath)
      do {
        files.append(
          try FileCollector.collect(
            source: source,
            path: fullPath,
            swiftLanguageMode: mode
          )
        )
      } catch {
        switch error {
        case let .didNotParse(diagnostics): parseDiagnostics += diagnostics
        case let .unreadable(path, reason):
          throw .unreadable(failures: [.init(path: path, reason: reason)])
        }
      }
    }
    guard parseDiagnostics.isEmpty else {
      throw CodebaseError.didNotParse(diagnostics: parseDiagnostics)
    }
    return files
  }

  static func contains(_ path: String, in directory: String) -> Bool {
    LexicalFilePath(directory).contains(LexicalFilePath(path))
  }

  private static func collect(
    _ path: String,
    from overlay: SourceOverlay,
    reusing reusable: ReusableFiles?,
    through parseCache: ParseCache?,
    swiftLanguageMode: SwiftLanguageMode
  ) async throws(ParseError) -> SourceFile {
    if let reused = reusable?.file(
      at: path,
      for: overlay,
      swiftLanguageMode: swiftLanguageMode
    ) {
      return reused
    }
    // Caching unsaved text would create disk entries for temporary edits.
    if let overlaid = overlay.text(forFileAt: path) {
      return try FileCollector.collect(
        source: overlaid,
        path: path,
        swiftLanguageMode: swiftLanguageMode
      )
    }
    if let parseCache {
      return try await parseCache.collect(
        at: path,
        swiftLanguageMode: swiftLanguageMode
      )
    }
    return try FileCollector.collect(
      fileAt: path,
      swiftLanguageMode: swiftLanguageMode
    )
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
    let rootPrefix = rootPath == "/" ? rootPath : rootPath + "/"
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
            paths.append(rootPrefix + relativePath)
          }
          return .descend
        }
      }
    return (
      paths,
      unopenable.map { directory in
        CodebaseError.ReadFailure(
          path: directory.relativePath.isEmpty
            ? rootPath : rootPrefix + directory.relativePath,
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
