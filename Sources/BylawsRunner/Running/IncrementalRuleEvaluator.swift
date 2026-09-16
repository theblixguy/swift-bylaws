import BylawsCore
import BylawsInterpreter
import BylawsPaths
import Foundation

enum IncrementalRuleEvaluator {
  private typealias Tracked = (
    value: Rule.Findings,
    dependencies: Set<RuleDependency>,
    isComplete: Bool
  )

  enum Error: Swift.Error {
    case cache(DiskCache.Error)
    case rule(RuleError)
  }

  static func findings(
    of rules: [Rule],
    program: RuleProgram,
    configuration: RuleRunConfiguration
  ) async throws(Error) -> [Rule.Findings] {
    guard var store = RuleResultStore.opening(
      program: program,
      configuration: configuration
    ) else {
      return try await findings(of: rules)
    }
    do {
      try store.removePersistedEntries()
    } catch {
      throw .cache(error)
    }
    let changedPaths = configuration.changedPaths.map {
      LexicalFilePath($0, relativeTo: configuration.root)
    }
    store.invalidateEntries(affectedBy: changedPaths)
    let cachedStore = store
    let evaluations = try await boundedConcurrentMap(
      rules,
      maximumConcurrentTasks: ProcessInfo.processInfo.activeProcessorCount
    ) { rule throws(Error) in
      if !changedPaths.isEmpty,
         let cached = cachedStore.entry(for: rule)
      {
        return Evaluation(findings: cached.findings, entry: cached)
      }
      let result = await trackedFindings(of: rule)
      let tracked: Tracked
      switch result {
      case let .success(value): tracked = value
      case let .failure(error):
        throw .rule(error)
      }
      let entry = tracked.isComplete
        ? RuleResultStore.Entry(
          findings: tracked.value,
          dependencies: tracked.dependencies
        )
        : nil
      return Evaluation(findings: tracked.value, entry: entry)
    }
    for (rule, evaluation) in zip(rules, evaluations) {
      store.setEntry(evaluation.entry, for: rule)
    }
    store.save()
    return evaluations.map(\.findings)
  }

  private static func findings(
    of rules: [Rule]
  ) async throws(Error) -> [Rule.Findings] {
    try await boundedConcurrentMap(
      rules,
      maximumConcurrentTasks: ProcessInfo.processInfo.activeProcessorCount
    ) { rule throws(Error) in
      let result = await findings(of: rule)
      switch result {
      case let .success(findings): return findings
      case let .failure(error): throw .rule(error)
      }
    }
  }

  private static func findings(
    of rule: Rule
  ) async -> Result<Rule.Findings, RuleError> {
    do {
      return .success(try await rule.findings())
    } catch {
      return .failure(error)
    }
  }

  private static func trackedFindings(
    of rule: Rule
  ) async -> Result<Tracked, RuleError> {
    do {
      return .success(try await RuleDependencyTracking.collecting {
        () async throws(RuleError) -> Rule.Findings in
        try await rule.findings()
      })
    } catch {
      return .failure(error)
    }
  }

  private struct Evaluation: Sendable {
    let findings: Rule.Findings
    let entry: RuleResultStore.Entry?
  }
}
