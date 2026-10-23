import BylawsPaths
import BylawsSemantics
import Foundation

package actor CodebaseCache {
  package static let shared = CodebaseCache()

  package func parsedCodebase(
    for codebase: Codebase
  ) async throws(CodebaseError) -> ParsedCodebase {
    do {
      let capture = try await SourceCapture.begin(codebase)
      let codebase = codebase.usingParseCache(
        SourceCapture.isEnabled ? .disabled : codebase.parseCachePolicy
          .resolved()
      )
      let key = try key(for: codebase, rootPath: capture?.scope.rootPath)
      let reusable = entries[key]?.reusableFiles
      let built = try await MemoisedTask.value(
        name: "bylaws: parse codebase",
        lookup: { entries[key]?.parsedCodebase },
        insert: { entries[key]?.parsedCodebase = $0 },
        remove: { entries[key]?.parsedCodebase = nil },
        storeValue: { built in
          entries[key]?.reusableFiles = CodebaseBuilder.ReusableFiles(
            overlay: codebase.overlay,
            filesByPath: built.rawFilesByPath
          )
        }
      ) { () async throws(CodebaseError) in
        try await CodebaseBuilder.build(codebase, reusing: reusable)
      }
      await codebase.recordSourceDependencies(rootPath: key.directoryRoot)
      try await SourceCapture.finish(
        capture, files: built.parsed.filesAsWritten,
        rootPath: built.parsed.rootPath,
        consumedInputs: built.languageInputs,
        xcodeProjects: built.xcodeProjects
      )
      return built.parsed
    } catch {
      throw await SourceCapture.failed(error, for: codebase)
    }
  }

  package func removeEntries(under directory: String) {
    entries = entries.filter { !$0.key.hasDirectoryRoot(under: directory) }
    canonicalKeys = canonicalKeys.filter {
      !$0.value.hasDirectoryRoot(under: directory)
    }
  }

  func packageAnalysis(
    for codebase: Codebase
  ) async throws(CodebaseError) -> PackageAnalysis {
    do {
      let codebase = codebase.usingParseCache(
        SourceCapture.isEnabled ? .disabled : codebase.parseCachePolicy
          .resolved()
      )
      let capturedCodebase: ParsedCodebase? = if SourceCapture.isEnabled {
        try await parsedCodebase(for: codebase)
      } else {
        nil
      }
      let key = try key(for: codebase, rootPath: capturedCodebase?.rootPath)
      let analysis = try await MemoisedTask.value(
        name: "bylaws: analyse package",
        lookup: { entries[key]?.packageAnalysis },
        insert: { entries[key]?.packageAnalysis = $0 },
        remove: { entries[key]?.packageAnalysis = nil }
      ) { [self] () async throws(CodebaseError) in
        let parsedCodebase = if let capturedCodebase { capturedCodebase }
        else { try await parsedCodebase(for: codebase) }
        return try CodebaseBuilder.packageAnalysis(
          of: parsedCodebase,
          from: codebase.overlay
        )
      }
      await codebase.recordSwiftPackageAnalysisDependencies(
        rootPath: key.directoryRoot
      )
      if let capturedCodebase {
        try await SourceCapture.record(
          [analysis.manifestInput], for: codebase,
          rootPath: capturedCodebase.rootPath
        )
      }
      return analysis
    } catch {
      throw await SourceCapture.failed(error, for: codebase)
    }
  }

  private struct Key: Sendable, Hashable {
    private enum Root: Sendable, Hashable {
      case directory(String)
      case sources(UUID)
    }

    private let root: Root
    private let including: Set<Glob>
    private let excluding: Set<Glob>
    private let parseCachePolicy: ParseCachePolicy
    private let swiftLanguageMode: Codebase.LanguageMode
    private let sourceLoading: SourceLoading

    var directoryRoot: String? {
      guard case let .directory(path) = root else { return nil }
      return path
    }

    init(_ codebase: Codebase, rootPath: String? = nil) throws(CodebaseError) {
      switch codebase.root.strategy {
      case .automatic, .directory:
        let path = if let rootPath { rootPath }
        else { try codebase.resolvedRootPath() }
        root = .directory(path)
      case .sources:
        root = .sources(codebase.root.cacheIdentity)
      }
      including = Set(codebase.including)
      excluding = Set(codebase.excluding)
      parseCachePolicy = codebase.parseCachePolicy
      swiftLanguageMode = codebase.swiftLanguageMode
      sourceLoading = codebase.sourceLoading
    }

    func hasDirectoryRoot(under directory: String) -> Bool {
      guard case let .directory(path) = root else { return false }
      return CodebaseBuilder.contains(path, in: directory)
    }
  }

  private struct LookupKey: Sendable, Hashable {
    private enum Root: Sendable, Hashable {
      case automatic(String)
      case directory(String)
      case sources(UUID)
    }

    private let root: Root
    private let including: Set<Glob>
    private let excluding: Set<Glob>
    private let parseCachePolicy: ParseCachePolicy
    private let swiftLanguageMode: Codebase.LanguageMode
    private let sourceLoading: SourceLoading

    init(_ codebase: Codebase) {
      root = switch codebase.root.strategy {
      case let .automatic(path):
        .automatic(LexicalFilePath(path, relativeTo: .currentDirectory).string)
      case let .directory(path):
        .directory(LexicalFilePath(path, relativeTo: .currentDirectory).string)
      case .sources:
        .sources(codebase.root.cacheIdentity)
      }
      including = Set(codebase.including)
      excluding = Set(codebase.excluding)
      parseCachePolicy = codebase.parseCachePolicy
      swiftLanguageMode = codebase.swiftLanguageMode
      sourceLoading = codebase.sourceLoading
    }
  }

  private struct Entry {
    let overlay: SourceOverlay
    var parsedCodebase: MemoisedTask<CodebaseBuilder.Build, CodebaseError>?
    var packageAnalysis: MemoisedTask<PackageAnalysis, CodebaseError>?
    var reusableFiles: CodebaseBuilder.ReusableFiles?
  }

  private var entries: [Key: Entry] = [:]

  private var canonicalKeys: [LookupKey: Key] = [:]

  var cachedConfigurationCount: Int { canonicalKeys.count }

  private func key(
    for codebase: Codebase, rootPath: String? = nil
  ) throws(CodebaseError) -> Key {
    let lookup = LookupKey(codebase)
    let key = if SourceCapture.isEnabled {
      try Key(codebase, rootPath: rootPath)
    } else if let canonical = canonicalKeys[lookup] {
      canonical
    } else {
      try Key(codebase)
    }
    canonicalKeys[lookup] = key
    if entries[key]?.overlay != codebase.overlay {
      entries[key] = Entry(
        overlay: codebase.overlay,
        reusableFiles: entries[key]?.reusableFiles
      )
    }
    return key
  }
}
