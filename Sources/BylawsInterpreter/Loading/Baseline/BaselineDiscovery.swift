public import BylawsCore
import BylawsPaths
import BylawsSemantics

/// A recorded baseline file found at the project root or beside a
/// module's `Package.swift`.
public struct DiscoveredBaseline: Sendable {
  /// The baseline file's path.
  public let path: String

  /// The directory where the baseline applies, relative to the project root.
  ///
  /// An empty path denotes the project-wide root baseline.
  public let relativeDirectory: String

  /// The accepted entries the file declares.
  public let entries: Set<Baseline.Entry>

  /// Creates a discovered baseline from its file, directory and entries.
  public init(
    path: String,
    relativeDirectory: String,
    entries: Set<Baseline.Entry>
  ) {
    self.path = path
    self.relativeDirectory = relativeDirectory
    self.entries = entries
  }

  package func applies(
    to filePath: String,
    underRoot rootPath: String
  ) -> Bool {
    relativeDirectory.isEmpty
      || LexicalFilePath(rootPath).appending(relativeDirectory)
      .contains(LexicalFilePath(filePath))
  }
}

/// The baselines a project declares and the diagnostics from loading them.
public struct DiscoveredBaselines: Sendable {
  /// The baselines that loaded, root baseline first.
  public let baselines: [DiscoveredBaseline]

  /// The errors for the files and directories that did not load.
  public let diagnostics: [Diagnostic]

  /// Creates the result of a baseline discovery.
  public init(baselines: [DiscoveredBaseline], diagnostics: [Diagnostic]) {
    self.baselines = baselines
    self.diagnostics = diagnostics
  }

  /// Returns the baselines the project's `Bylaws.baseline.swift` files
  /// declare.
  ///
  /// Discovery checks the project root and each directory containing a
  /// `Package.swift`. A module baseline applies only within that module. The
  /// root baseline applies project-wide.
  ///
  /// Read ``diagnostics`` for files that failed to load.
  public static func discovered(
    atRoot rootPath: String
  ) async -> DiscoveredBaselines {
    await discovered(atRoot: rootPath, overlay: .empty)
  }

  package static func discovered(
    atRoot rootPath: String,
    overlay: SourceOverlay
  ) async -> DiscoveredBaselines {
    var baselines: [DiscoveredBaseline] = []
    let discovery = await RulesDiscovery.baselineFiles(
      underRoot: rootPath,
      overlay: overlay
    )
    var diagnostics = discovery.diagnostics
      + (discovery.parsedRoot?.diagnostics ?? [])
    for file in discovery.files {
      let loaded = loaded(
        from: file.path,
        relativeDirectory: file.relativeDirectory
      )
      baselines += loaded.baselines
      diagnostics += loaded.diagnostics
    }
    return DiscoveredBaselines(baselines: baselines, diagnostics: diagnostics)
  }

  /// Returns the explicit baseline file when one is given, or the
  /// discovered baselines otherwise.
  ///
  /// An explicit file replaces discovery and applies to every directory. With
  /// no explicit baseline, an empty `rootPath` disables discovery and accepts
  /// no violations.
  ///
  /// Read ``diagnostics`` for files that failed to load.
  public static func accepted(
    from explicitFile: String?,
    atRoot rootPath: String
  ) async -> DiscoveredBaselines {
    await accepted(from: explicitFile, atRoot: rootPath, overlay: .empty)
  }

  package static func accepted(
    from explicitFile: String?,
    atRoot rootPath: String,
    overlay: SourceOverlay
  ) async -> DiscoveredBaselines {
    guard let explicitFile else {
      guard !rootPath.isEmpty else {
        return DiscoveredBaselines(baselines: [], diagnostics: [])
      }
      return await discovered(atRoot: rootPath, overlay: overlay)
    }
    return loaded(from: explicitFile, relativeDirectory: "")
  }

  private static func loaded(
    from path: String,
    relativeDirectory: String
  ) -> DiscoveredBaselines {
    do {
      let entries = try Baseline.entries(fromFile: path)
      let baseline = DiscoveredBaseline(
        path: path,
        relativeDirectory: relativeDirectory,
        entries: Set(entries)
      )
      return DiscoveredBaselines(baselines: [baseline], diagnostics: [])
    } catch {
      return DiscoveredBaselines(baselines: [], diagnostics: error.diagnostics)
    }
  }
}

extension Violations<Offender> {
  /// Returns the same violations without the offenders the baselines
  /// accept for the rule with `ruleID`.
  ///
  /// A baseline accepts an offender only when the affected file or folder is
  /// in the directory where the baseline applies.
  public func removingOffenders(
    acceptedBy baselines: [DiscoveredBaseline],
    for ruleID: Rule.ID,
    under rootPath: String
  ) -> Violations<Offender> {
    Violations(
      rule: rule,
      offenders: offenders.filter { offender in
        !baselines.contains { baseline in
          baseline.applies(
            to: offender.affectedPath ?? offender.location.filePath,
            underRoot: rootPath
          )
            && baseline.entries.contains(
              Baseline.Entry(
                offender: offender,
                for: ruleID,
                relativeTo: rootPath
              )
            )
        }
      },
      checkedCount: checkedCount
    )
  }
}
