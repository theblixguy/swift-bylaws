import BylawsCore
import BylawsInterpreter
import BylawsPaths
import BylawsSemantics
import Foundation

struct RuleResultStore: Sendable {
  private static let schemaVersion = 1

  struct Entry: Codable, Sendable {
    let checks: [Violations<Offender>]
    let warnings: [Rule.Warning]
    let dependencies: Set<RuleDependency>

    init(
      findings: Rule.Findings,
      dependencies: Set<RuleDependency>
    ) {
      checks = findings.checks
      warnings = findings.warnings
      self.dependencies = dependencies
    }

    var findings: Rule.Findings {
      Rule.Findings(checks: checks, warnings: warnings)
    }

    func isAffected(by paths: [LexicalFilePath]) -> Bool {
      dependencies.contains { dependency in
        paths.contains(where: dependency.contains(path:))
      }
    }
  }

  private struct RuleKey: Codable, Hashable, Sendable {
    let id: Rule.ID
    let location: DeclarationLocation

    init(_ rule: Rule) {
      id = rule.id
      location = rule.location
    }
  }

  private struct Snapshot: Codable {
    let schemaVersion: Int
    let programFingerprint: String
    let entries: [RuleKey: Entry]
  }

  private let cache: DiskCache
  private let entryName: String
  private let programFingerprint: String
  private var entries: [RuleKey: Entry]

  static func opening(
    program: RuleProgram,
    configuration: RuleRunConfiguration
  ) -> Self? {
    guard configuration.overlay.isEmpty,
          let sourcePaths = program.ruleSourcePaths,
          let settings = configuration.parseCachePolicy.settings(
            forRoot: configuration.root.string
          ),
          let cache = try? DiskCache.opening(
            directory: settings.directory,
            budget: settings.budget
          ),
          let fingerprint = fingerprint(
            sourcePaths: sourcePaths,
            configuration: configuration
          )
    else { return nil }
    let rootKey = DiskCache.key(for: configuration.root.string)
    let entryName = "rule-results-\(rootKey).json"
    let file = cache.data(forEntryNamed: entryName).flatMap {
      try? JSONDecoder().decode(Snapshot.self, from: $0)
    }
    return RuleResultStore(
      cache: cache,
      entryName: entryName,
      programFingerprint: fingerprint,
      entries: file?.schemaVersion == schemaVersion
        && file?.programFingerprint == fingerprint
        ? file?.entries ?? [:]
        : [:]
    )
  }

  func entry(for rule: Rule) -> Entry? {
    entries[RuleKey(rule)]
  }

  mutating func setEntry(_ entry: Entry?, for rule: Rule) {
    entries[RuleKey(rule)] = entry
  }

  mutating func invalidateEntries(affectedBy paths: [LexicalFilePath]) {
    guard !paths.isEmpty else { return }
    entries = entries.filter { !$0.value.isAffected(by: paths) }
  }

  func removePersistedEntries() throws(DiskCache.Error) {
    try cache.removeEntry(named: entryName)
  }

  func save() {
    let snapshot = Snapshot(
      schemaVersion: Self.schemaVersion,
      programFingerprint: programFingerprint,
      entries: entries
    )
    guard let data = try? JSONEncoder().encode(snapshot) else { return }
    try? cache.write(data, toEntryNamed: entryName)
  }

  private static func fingerprint(
    sourcePaths: [String],
    configuration: RuleRunConfiguration
  ) -> String? {
    let paths = Set(
      sourcePaths + [configuration.swiftPackageModules]
        .compactMap(\.self)
    ).sorted()
    guard !paths.isEmpty else { return nil }
    var text = BylawsVersion.current
      + (configuration.sourceOnly ? "\nsource-only\n" : "\nindexed\n")
    for path in paths {
      guard let source = try? String(contentsOfFile: path, encoding: .utf8)
      else { return nil }
      text += "\(path.utf8.count):\(path)\(source.utf8.count):\(source)"
    }
    return DiskCache.key(for: text)
  }
}
