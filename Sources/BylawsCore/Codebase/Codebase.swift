import BylawsSemantics
package import BylawsPaths
import Foundation

/// The Swift source files that rules query and lint.
///
/// A codebase names a root directory and the globs that narrow the files
/// under it. Query accessors such as ``classes``, ``functions`` and
/// ``imports`` return the declarations in those files as a ``Selection``
/// to filter and check.
///
/// Initialisation defers file access. Without an explicit cache configuration,
/// the first query uses the enclosing `.parseCache` trait's defaults or reads
/// `BYLAWS_DISABLE_PARSE_CACHE` and `BYLAWS_CACHE_PATH`.
/// Parsed data remains in memory for the process.
///
/// An unreadable file or directory fails the query with
/// ``CodebaseError/unreadable(failures:)``. A syntax error fails it with
/// ``CodebaseError/didNotParse(diagnostics:)``. A rule runs only over a complete
/// model.
public struct Codebase: Sendable, Hashable {
  /// A strategy for locating the codebase's root directory.
  public struct Root: Sendable, Hashable {
    enum Strategy: Sendable, Hashable {
      case automatic(callerFilePath: String)
      case directory(String)
      case sources([String: String])
    }

    let strategy: Strategy
    let cacheIdentity: UUID

    /// Returns a root at the nearest ancestor of `filePath` that
    /// contains `Package.swift`, an Xcode project, `.git` or a Bazel workspace.
    /// Bazel markers are `MODULE.bazel`, `WORKSPACE.bazel` and `WORKSPACE`.
    public static func automatic(above filePath: String = #filePath) -> Root {
      Root(strategy: .automatic(callerFilePath: filePath))
    }

    /// Returns a root at an explicit directory path.
    public static func directory(_ path: String) -> Root {
      Root(strategy: .directory(path))
    }

    /// Returns a root of source files given directly, keyed by relative
    /// path.
    ///
    /// Use this to test your own matchers, queries and layerings against
    /// small codebases written inline:
    ///
    /// ```swift
    /// let codebase = Codebase(root: .sources([
    ///   "Sources/App/A.swift": "final class A {}",
    /// ]))
    /// ```
    public static func sources(_ files: [String: String]) -> Root {
      Root(strategy: .sources(files))
    }

    /// Returns whether two roots locate their files the same way.
    ///
    /// - Parameters:
    ///   - lhs: The first root.
    ///   - rhs: The second root.
    public static func == (lhs: Root, rhs: Root) -> Bool {
      lhs.strategy == rhs.strategy
    }

    /// Hashes the way the root locates its files.
    ///
    /// - Parameter hasher: The hasher to combine the root into.
    public func hash(into hasher: inout Hasher) {
      hasher.combine(strategy)
    }

    private init(strategy: Strategy, cacheIdentity: UUID = UUID()) {
      self.strategy = strategy
      self.cacheIdentity = cacheIdentity
    }
  }

  /// The root-resolution strategy.
  public let root: Root

  /// The globs a file must match to be included.
  ///
  /// An empty list includes every file.
  public let including: [Glob]

  /// The globs that remove files from the codebase.
  public let excluding: [Glob]

  /// The language mode or project settings to use when parsing files.
  ///
  /// The default, `.automatic(.swiftPM)`, reads SwiftPM settings and uses
  /// Swift 6 for files without applicable settings.
  public let swiftLanguageMode: LanguageMode

  package private(set) var parseCachePolicy: ParseCachePolicy

  package private(set) var overlay: SourceOverlay

  package var sourceLoading: SourceLoading

  package private(set) var declarations: ParsedCodebase.Declarations = .resolved

  /// Creates a codebase at `root` with include and exclude globs.
  ///
  /// Set `swiftLanguageMode` to `.v4`, `.v5` or `.v6` to skip discovery in
  /// tests, the CLI and the editor.
  ///
  /// Set `parseCache` to choose a disk cache directory, cleanup target and
  /// validation policy.
  /// A `nil` value uses the enclosing `.parseCache` trait's defaults or the
  /// environment settings.
  public init(
    root: Root = .automatic(),
    including: [Glob] = [],
    excluding: [Glob] = [],
    swiftLanguageMode: LanguageMode = .automatic(.swiftPM),
    parseCache: ParseCacheConfiguration? = nil
  ) {
    self.root = root
    self.including = including
    self.excluding = excluding
    self.swiftLanguageMode = swiftLanguageMode
    parseCachePolicy = parseCache.map { .configured($0) } ?? .environment()
    overlay = .empty
    sourceLoading = .fileSystem
  }

  package func covers(_ path: Glob.Path) -> Bool {
    let included = including.isEmpty || including.contains { $0.matches(path) }
    return included && !excluding.contains { $0.matches(path) }
  }

  package func usingParseCache(_ policy: ParseCachePolicy) -> Codebase {
    var codebase = self
    codebase.parseCachePolicy = policy
    return codebase
  }

  package func usingOverlay(_ overlay: SourceOverlay) -> Codebase {
    var codebase = self
    codebase.overlay = overlay
    return codebase
  }

  package func usingDeclarations(
    _ declarations: ParsedCodebase.Declarations
  ) -> Codebase {
    var codebase = self
    codebase.declarations = declarations
    return codebase
  }

  /// The codebase bound by the enclosing suite's `.codebase(_:)` trait.
  ///
  /// Outside a suite with that trait, the value is `nil`.
  @TaskLocal public static var current: Codebase?

  /// Parses the codebase eagerly.
  ///
  /// Later accessors return immediately.
  ///
  /// - Throws: ``CodebaseError`` when the root cannot be resolved, the root
  ///   is not a directory, or a source file cannot be read or parsed.
  public func prepare() async throws(CodebaseError) {
    let parsed = try await CodebaseCache.shared.parsedCodebase(for: self)
    _ = await parsed.resolvedFiles()
  }

  package func resolvedRootPath() throws(CodebaseError) -> String {
    switch root.strategy {
    case let .directory(path):
      var isDirectory: ObjCBool = false
      guard unsafe FileManager.default.fileExists(
        atPath: path,
        isDirectory: &isDirectory
      ),
        isDirectory.boolValue
      else { throw .notADirectory(path: path) }
      return Self.standardisedPath(path)
    case let .automatic(callerFilePath):
      return try Self.automaticRoot(above: callerFilePath)
    case .sources:
      return Self.sourcesRootPath
    }
  }

  package static func automaticRoot(
    above callerFilePath: String
  ) throws(CodebaseError) -> String {
    try automaticRoot(
      at: absolutePath(callerFilePath).removingLastComponent(),
      searchedFrom: callerFilePath
    )
  }

  package static func automaticRoot(
    at directory: LexicalFilePath
  ) throws(CodebaseError) -> String {
    try automaticRoot(at: directory, searchedFrom: directory.string)
  }

  private static func automaticRoot(
    at directory: LexicalFilePath,
    searchedFrom origin: String
  ) throws(CodebaseError) -> String {
    var directory = directory
    while directory.string != "/" {
      if try containsProjectMarker(directory) { return directory.string }
      directory = directory.removingLastComponent()
    }
    throw .rootNotFound(searchedFrom: origin)
  }

  // Inline sources need stable paths for globs and source locations.
  package static let sourcesRootPath = "/virtual"

  private static func standardisedPath(_ path: String) -> String {
    absolutePath(path).string
  }

  private static func absolutePath(_ path: String) -> LexicalFilePath {
    LexicalFilePath(path, relativeTo: .currentDirectory)
  }

  private static func containsProjectMarker(
    _ directory: LexicalFilePath
  ) throws(CodebaseError) -> Bool {
    let contents: [String]
    do {
      contents = try FileManager.default
        .contentsOfDirectory(atPath: directory.string)
    } catch {
      let error = error as NSError
      if error.domain == NSCocoaErrorDomain,
         error.code == NSFileNoSuchFileError
         || error.code == NSFileReadNoSuchFileError
      {
        return false
      }
      throw .unreadable(failures: [
        .init(path: directory.string, reason: error.reportableDescription),
      ])
    }
    return contents.contains { name in
      switch name {
      case "Package.swift", ".git", "MODULE.bazel", "WORKSPACE.bazel",
           "WORKSPACE": true
      default: name.hasSuffix(".xcodeproj")
      }
    }
  }
}
