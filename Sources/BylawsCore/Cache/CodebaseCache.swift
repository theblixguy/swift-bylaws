import BylawsPaths
import BylawsSemantics
import Foundation

package actor CodebaseCache {
  package static let shared = CodebaseCache()

  package func parsedCodebase(
    for codebase: Codebase
  ) async throws(CodebaseError) -> ParsedCodebase {
    let codebase = codebase.usingParseCache(
      codebase.parseCachePolicy.resolved()
    )
    let key = try key(for: codebase)
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
    return built.parsed
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
    let codebase = codebase.usingParseCache(
      codebase.parseCachePolicy.resolved()
    )
    let key = try key(for: codebase)
    return try await MemoisedTask.value(
      name: "bylaws: analyse package",
      lookup: { entries[key]?.packageAnalysis },
      insert: { entries[key]?.packageAnalysis = $0 },
      remove: { entries[key]?.packageAnalysis = nil }
    ) { [self] () async throws(CodebaseError) in
      let parsedCodebase = try await parsedCodebase(for: codebase)
      return try CodebaseBuilder.packageAnalysis(
        of: parsedCodebase,
        from: codebase.overlay
      )
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

    init(_ codebase: Codebase) throws(CodebaseError) {
      switch codebase.root.strategy {
      case .automatic, .directory:
        root = .directory(try codebase.resolvedRootPath())
      case .sources:
        root = .sources(codebase.root.cacheIdentity)
      }
      including = Set(codebase.including)
      excluding = Set(codebase.excluding)
      parseCachePolicy = codebase.parseCachePolicy
      swiftLanguageMode = codebase.swiftLanguageMode
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

  private func key(for codebase: Codebase) throws(CodebaseError) -> Key {
    let lookup = LookupKey(codebase)
    let key: Key
    if let canonical = canonicalKeys[lookup] {
      key = canonical
    } else {
      key = try Key(codebase)
      canonicalKeys[lookup] = key
    }
    if entries[key]?.overlay != codebase.overlay {
      entries[key] = Entry(
        overlay: codebase.overlay,
        reusableFiles: entries[key]?.reusableFiles
      )
    }
    return key
  }
}
