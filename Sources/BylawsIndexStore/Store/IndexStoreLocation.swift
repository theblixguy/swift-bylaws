package import BylawsPaths
public import Foundation

/// Locates the index store written by a build.
///
/// Debug builds write the store. Release builds require
/// `--enable-index-store`. A rule that reads the index needs that build output.
public enum IndexStoreLocation {
  /// The name of the environment variable that names a store outright.
  ///
  /// Set `BYLAWS_INDEX_STORE` when the build writes its store outside the
  /// paths ``path(forPackageContaining:environment:)`` searches, such as a
  /// CI job with its own derived-data path.
  public static let environmentKey = "BYLAWS_INDEX_STORE"

  /// Locates the running build's index store, starting from `file`.
  ///
  /// Search stops at the first matching store, using this order:
  ///
  /// 1. The `BYLAWS_INDEX_STORE` environment variable.
  /// 2. Xcode's `INDEX_DATA_STORE_DIR`, an explicit store path.
  /// 3. The derived-data directory containing Xcode's build paths, for runs
  ///    from Xcode and `xcodebuild`.
  /// 4. The SwiftPM build directory containing the running executable,
  ///    including builds with a custom `--scratch-path`.
  /// 5. The `.build` directory of the package that holds `file`, for
  ///    `swift test` in its standard location.
  ///
  /// Passing `#filePath` from a rule starts the package search at the test
  /// file.
  ///
  /// - Throws: ``IndexStoreError/missingStore(searched:)`` with the checked
  ///   paths when no store is found, or
  ///   ``IndexStoreError/unreadablePath(path:reason:)`` when discovery cannot
  ///   inspect a candidate path.
  public static func path(
    forPackageContaining file: String,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws(IndexStoreError) -> String {
    try discoverPath(
      environment: environment,
      packageStore: { () throws(IndexStoreError) in
        try forPackage(
          containing: LexicalFilePath(file, relativeTo: .currentDirectory),
          executablePath: CommandLine.arguments.first,
          workingDirectory: .currentDirectory
        )
      }
    )
  }

  /// Searches for the index store under `packageRoot`.
  ///
  /// The search follows ``path(forPackageContaining:environment:)`` but
  /// starts from the given package root.
  ///
  /// - Throws: ``IndexStoreError/missingStore(searched:)`` with the checked
  ///   paths when no store is found, or
  ///   ``IndexStoreError/unreadablePath(path:reason:)`` when discovery cannot
  ///   inspect a candidate path.
  public static func path(
    forPackageAt packageRoot: String,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws(IndexStoreError) -> String {
    try discoverPath(
      environment: environment,
      packageStore: { () throws(IndexStoreError) in
        try forPackage(
          at: LexicalFilePath(packageRoot, relativeTo: .currentDirectory),
          executablePath: CommandLine.arguments.first,
          workingDirectory: .currentDirectory
        )
      }
    )
  }

  /// Returns the path of the index library in the active toolchain, or
  /// `nil` when the toolchain holds none.
  ///
  /// Bylaws loads the active toolchain's library at run time.
  public static func toolchainLibraryPath() -> String? {
    ToolchainPaths.indexStoreLibraryPath()
  }

  private static func discoverPath(
    environment: [String: String],
    packageStore: () throws(IndexStoreError) -> String
  ) throws(IndexStoreError) -> String {
    if let path = try explicitStore(in: environment) { return path }
    let found = try derivedDataStore(in: environment)
    if let path = found.path { return path }
    do {
      return try packageStore()
    } catch {
      throw error.addingSearchedPaths(found.searched)
    }
  }

  package static func forPackage(
    at package: LexicalFilePath,
    executablePath: String?,
    workingDirectory: LexicalFilePath
  ) throws(IndexStoreError) -> String {
    var searched: [String] = []
    if let executablePath, workingDirectory == package,
       let candidate = IndexStoreCandidates.runningBuildStore(
         besideExecutableAt: LexicalFilePath(
           executablePath,
           relativeTo: workingDirectory
         )
       )
    {
      searched.append(candidate.string)
      if try IndexStoreDirectory.isStore(candidate) { return candidate.string }
    }

    let build = package.appending(".build")
    let entries = try IndexStoreDirectory.directoryContents(at: build) ?? []
    var newest: (path: String, date: Date)?
    for candidate in IndexStoreCandidates.packageStores(
      inBuildDirectory: build,
      entries: entries
    ) {
      searched.append(candidate.string)
      guard try IndexStoreDirectory.isStore(candidate),
            let written = try IndexStoreDirectory.lastWritten(candidate)
      else { continue }
      if newest.map({ written > $0.date }) ?? true {
        newest = (candidate.string, written)
      }
    }

    if let newest { return newest.path }
    throw .missingStore(searched: searched.isEmpty ? [build.string] : searched)
  }

  static func forPackage(
    containing file: LexicalFilePath,
    executablePath: String?,
    workingDirectory: LexicalFilePath
  ) throws(IndexStoreError) -> String {
    var directory = file.removingLastComponent()
    while directory.lastComponent != nil {
      let manifest = directory.appending("Package.swift")
      if FileManager.default.fileExists(atPath: manifest.string) {
        return try forPackage(
          at: directory,
          executablePath: executablePath,
          workingDirectory: workingDirectory
        )
      }
      directory = directory.removingLastComponent()
    }
    throw .missingStore(searched: [file.string])
  }

  private static func explicitStore(
    in environment: [String: String]
  ) throws(IndexStoreError) -> String? {
    guard let path = environment[environmentKey] else { return nil }
    guard try IndexStoreDirectory.isStore(LexicalFilePath(path))
    else { throw .missingStore(searched: [path]) }
    return path
  }

  private static func derivedDataStore(
    in environment: [String: String]
  ) throws(IndexStoreError) -> (path: String?, searched: [String]) {
    var searched: [String] = []
    if let path = environment["INDEX_DATA_STORE_DIR"] {
      searched.append(path)
      if try IndexStoreDirectory.isStore(LexicalFilePath(path)) {
        return (path, searched)
      }
    }
    for anchor in IndexStoreCandidates.xcodeBuildDirectories(in: environment) {
      for candidate in IndexStoreCandidates.derivedDataStores(
        above: LexicalFilePath(anchor)
      ) {
        if try IndexStoreDirectory.isStore(candidate) {
          return (candidate.string, searched)
        }
        searched.append(candidate.string)
      }
    }
    return (nil, searched)
  }
}
