package import BylawsCore
package import BylawsPaths
import BylawsSemantics
import Foundation

extension RuleProgram {
  /// Loads the program declared by a project's `Bylaws.swift` files.
  ///
  /// A rules file applies to its folder and can override rules from parent
  /// folders. The nearest override applies when folders are nested.
  ///
  /// Read ``RuleProgram/diagnostics`` for missing files and load failures.
  /// ``BylawsCore/Rule/discovered(above:)`` uses the same discovery and throws
  /// instead.
  ///
  /// - Parameter rootPath: The project root. A relative path resolves
  ///   against the working directory.
  ///
  /// ## See Also
  ///
  /// - ``BylawsCore/Rule/discovered(above:)``
  public static func discovered(atRoot rootPath: String) async -> RuleProgram {
    await discovered(
      atRoot: LexicalFilePath(rootPath, relativeTo: .currentDirectory),
      parseCachePolicy: .environment(),
      indexProvider: nil,
      packageModuleIndex: nil
    )
  }

  package static func discovered(
    atRoot root: LexicalFilePath,
    parseCachePolicy: ParseCachePolicy,
    overlay: SourceOverlay = .empty,
    indexProvider: (any RuntimeIndexProvider)? = nil,
    packageModuleIndex: PackageModuleIndex? = nil
  ) async -> RuleProgram {
    let rootPath = root.string
    let discovery = await RulesDiscovery.rulesFiles(
      underRoot: rootPath,
      overlay: overlay
    )
    guard discovery.diagnostics.isEmpty else {
      return RuleProgram(loadedRules: [], diagnostics: discovery.diagnostics)
    }
    let files = discovery.files
    guard !files.isEmpty else {
      return RuleProgram(
        loadedRules: [],
        diagnostics: [
          .error(
            "no \(RulesDiscovery.fileName) found",
            at: DeclarationLocation.start(
              of: "\(rootPath)/\(RulesDiscovery.fileName)"
            ),
            hint: "add a Bylaws.swift file at the project root or in a folder to check"
          ),
        ],
        ruleFileStatus: .missing
      )
    }
    return await RuleProgramLoader.load(
      files,
      parsedRoot: discovery.parsedRoot,
      parseCachePolicy: parseCachePolicy,
      overlay: overlay,
      indexProvider: indexProvider,
      packageModuleIndex: packageModuleIndex
    )
  }

  /// Loads a program from explicit rules files without
  /// discovery.
  ///
  /// Explicit files form a flat hierarchy. Each uses its own directory as the
  /// codebase root, and rule IDs must be unique across files.
  ///
  /// Read ``RuleProgram/diagnostics`` for files that failed to load.
  ///
  /// - Parameter paths: The rules files. A relative path resolves against
  ///   the working directory.
  public static func loaded(fromFiles paths: [String]) async -> RuleProgram {
    await loaded(
      fromFiles: paths
        .map { LexicalFilePath($0, relativeTo: .currentDirectory) },
      parseCachePolicy: .environment(),
      indexProvider: nil,
      packageModuleIndex: nil
    )
  }

  package static func loaded(
    fromFiles paths: [LexicalFilePath],
    parseCachePolicy: ParseCachePolicy,
    overlay: SourceOverlay = .empty,
    indexProvider: (any RuntimeIndexProvider)? = nil,
    packageModuleIndex: PackageModuleIndex? = nil
  ) async -> RuleProgram {
    await RuleProgramLoader.load(
      paths.map { path in
        RulesDiscovery.DiscoveredFile(path: path.string, relativeDirectory: "")
      },
      parseCachePolicy: parseCachePolicy,
      overlay: overlay,
      indexProvider: indexProvider,
      packageModuleIndex: packageModuleIndex
    )
  }
}
