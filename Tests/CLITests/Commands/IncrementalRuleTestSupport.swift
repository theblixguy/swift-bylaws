import BylawsCore
import BylawsInterpreter
import BylawsPaths
import BylawsSemantics
import Foundation
import Testing
@testable import BylawsRunner

func incrementalRule(
  id: Rule.ID,
  path: String,
  counts: InvocationCounts,
  countKey: String? = nil,
  location: DeclarationLocation? = nil
) -> Rule {
  let codebase = Codebase(
    root: .directory(path),
    swiftLanguageMode: .v6
  )
  return Rule(id, "Classes are final", location: location) {
    await counts.increment(countKey ?? id.rawValue)
    return Violations(of: .isFinal, in: try await codebase.classes)
  }
}

func incrementalProgram(
  rules: [Rule],
  sourcePath: String
) -> RuleProgram {
  RuleProgram(
    loadedRules: rules.map(RuleProgram.LoadedRule.init(unscoped:)),
    diagnostics: [],
    ruleFileStatus: .found,
    ruleSourcePaths: [sourcePath]
  )
}

func incrementalConfiguration(
  root: URL,
  cache: URL
) -> RuleRunConfiguration {
  RuleRunConfiguration(
    root: LexicalFilePath(root.path),
    parseCachePolicy: .enabled(
      directory: cache,
      cachesTemporaryRoots: true
    )
  )
}

func resultCacheFile(in cache: URL) throws -> URL {
  try #require(
    FileManager.default.contentsOfDirectory(
      at: cache.appendingPathComponent("Bylaws"),
      includingPropertiesForKeys: nil
    ).first { $0.lastPathComponent.hasPrefix("rule-results-") }
  )
}

actor InvocationCounts {
  private var values: [String: Int] = [:]

  func increment(_ key: String) {
    values[key, default: 0] += 1
  }

  func value(for key: String) -> Int {
    values[key, default: 0]
  }
}
