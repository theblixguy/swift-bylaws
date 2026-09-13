public import Foundation

/// A problem reading the compiler's index store.
///
/// Later versions may add cases.
@nonexhaustive
public enum IndexStoreError: Error, Sendable, Hashable {
  /// The dynamic loader's `reason` for failing to open the index library at
  /// `path`.
  case unreadableLibrary(path: String, reason: String)

  /// The index library does not export `symbol`.
  case unsupportedLibrary(symbol: String)

  /// The active toolchain holds no index library.
  case missingLibrary

  /// The index library failed to open the store at `path` and supplied
  /// `reason`.
  case unreadableStore(path: String, reason: String)

  /// Discovery could not inspect the file or directory at `path`.
  case unreadablePath(path: String, reason: String)

  /// Opening unit `name` failed with the index library's `reason`.
  case unreadableUnit(name: String, reason: String)

  /// The index library's `reason` for failing to open record `name`.
  case unreadableRecord(name: String, reason: String)

  /// No store unit belongs to a module in `names`.
  ///
  /// The `available` set names the modules the store contains.
  case missingModules(names: Set<String>, available: Set<String>)

  /// Several builds of one source file, identified by their output identities.
  case mixedBuildConfigurations(
    module: String,
    file: String,
    outputFiles: Set<String>
  )

  /// The store contains no unit for the output identities in `outputFiles`.
  case missingUnitOutputFiles(outputFiles: Set<String>)

  /// The search found no index store.
  ///
  /// `searched` names the paths it looked in.
  case missingStore(searched: [String])
}

extension IndexStoreError {
  package func addingSearchedPaths(_ paths: [String]) -> Self {
    guard case let .missingStore(searched) = self else { return self }
    return .missingStore(searched: paths + searched)
  }
}

extension IndexStoreError: CustomStringConvertible {
  /// A message that names the problem and the fix where there is one.
  public var description: String {
    switch self {
    case let .unreadableLibrary(path, reason):
      "The index library at '\(path)' did not open. The dynamic loader "
        + "reported: \(reason). Check that the file exists and belongs to "
        + "the Swift toolchain that built the store."
    case let .unsupportedLibrary(symbol):
      "The index library in this toolchain exports no '\(symbol)'. Check "
        + "that Swift uses the toolchain that built the store. Update Bylaws "
        + "when that toolchain is newer than this release."
    case .missingLibrary:
      "The active Swift toolchain holds no index library. Run 'which swiftc' "
        + "to check the active compiler."
    case let .unreadableStore(path, reason):
      "The index store at '\(path)' did not open. The index library "
        + "reported: \(reason)."
    case let .unreadablePath(path, reason):
      "The index store search could not inspect '\(path)': \(reason)."
    case let .unreadableUnit(name, reason):
      "The index unit '\(name)' did not open. The index library reported: "
        + "\(reason)."
    case let .unreadableRecord(name, reason):
      "The index record '\(name)' did not open. The index library reported: "
        + "\(reason)."
    case let .missingModules(names, available):
      "The index store contains no unit for these requested modules: "
        + "\(names.sorted().joined(separator: ", ")). The available modules "
        + "are: \(available.sorted().joined(separator: ", "))."
    case let .mixedBuildConfigurations(module, file, outputFiles):
      "The index store contains several builds of '\(file)' in module "
        + "'\(module)': \(outputFiles.sorted().joined(separator: ", ")). "
        + "Pass the current build's unit output identities to ProjectIndex, "
        + "or use a store that belongs to one build configuration."
    case let .missingUnitOutputFiles(outputFiles):
      "The index store contains no unit for these output identities: "
        + "\(outputFiles.sorted().joined(separator: ", ")). Check that the "
        + "identities and the store come from the same build."
    case let .missingStore(searched):
      """
      The index store for this build is missing. Build the project in debug \
      to create it. Set \(IndexStoreLocation
        .environmentKey) to the \
      store's path when your build writes the store outside the paths \
      below.

      The search covered these paths:
      \(searched.indentedLines(atMost: 5))
      """
    }
  }
}

extension [String] {
  fileprivate func indentedLines(atMost limit: Int) -> String {
    let shown = prefix(limit)
      .map { "  \($0)" }
      .joined(separator: "\n")
    guard count > limit else { return shown }
    return shown + "\n  and \(count - limit) more"
  }
}

extension IndexStoreError: LocalizedError {
  /// The same message as ``description``.
  public var errorDescription: String? { description }
}
