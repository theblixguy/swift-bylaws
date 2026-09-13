import BylawsCore
import BylawsSemantics

enum RuntimeProgramCompiler {
  static func compile(
    _ value: RuntimeRule,
    in file: ParsedRulesFile,
    indexProvider: (any RuntimeIndexProvider)? = nil,
    excludingSubtrees: [String] = []
  ) -> Rule {
    makeRule(
      id: value.id,
      name: value.name,
      enforcement: value.enforcement,
      hint: value.hint,
      location: value.location,
      codebases: file.codebases,
      excludingSubtrees: excludingSubtrees
    ) {
      try await findings(of: value, indexProvider: indexProvider)
    }
  }

  private static func findings(
    of value: RuntimeRule,
    indexProvider: (any RuntimeIndexProvider)?
  ) async throws -> Rule.Findings {
    let evaluator = RuntimeEvaluator(
      globals: value.body.captures,
      indexProvider: indexProvider
    )
    var state = RuntimeEvaluationState(limits: .standard)
    let result: RuntimeValue
    do {
      result = try await evaluator.invoke(
        value.body,
        arguments: [],
        builder: .checks,
        state: &state
      )
    } catch {
      // The runner tells a cancelled run apart from a failed rule.
      if error.kind == .cancelled { throw CancellationError() }
      throw error
    }
    return try findings(from: result, at: value.location)
  }

  private static func makeRule(
    id: String,
    name: String,
    enforcement: Enforcement,
    hint: String?,
    location: DeclarationLocation,
    codebases: [String: Codebase],
    excludingSubtrees: [String],
    findings body: @escaping @Sendable () async throws -> Rule.Findings
  ) -> Rule {
    Rule(
      Rule.ID(id),
      name,
      enforcement: enforcement,
      hint: hint,
      location: location,
      body: {
        let findings = try await body()
        guard !excludingSubtrees.isEmpty else { return findings }
        let excluded = try ExcludedSubtrees(
          subtrees: excludingSubtrees,
          under: codebases.values.map { try $0.resolvedRootPath() }
        )
        return excluded.filteringOffenders(from: findings)
      }
    )
  }

  private static func findings(
    from value: RuntimeValue,
    at location: DeclarationLocation
  ) throws(RuntimeError) -> Rule.Findings {
    guard let result = value.ruleResult else {
      throw RuntimeError(
        message: "Rule must return a check result, Violations or Rule.Findings",
        location: location
      )
    }
    return result.findings(reportedAt: location)
  }
}
