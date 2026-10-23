import BylawsCore
import BylawsPaths
import BylawsSemantics

enum RuntimeProgramCompiler {
  static func compile(
    _ value: RuntimeRule,
    in file: ParsedRulesFile,
    indexProvider: (any RuntimeIndexProvider)? = nil,
    runtimeContext: RuntimeProgramContext? = nil,
    excludingSubtrees: [String] = []
  ) -> Rule {
    let excluded = ExcludedSubtrees(
      subtrees: excludingSubtrees,
      under: [LexicalFilePath(file.path).removingLastComponent().string]
    )
    return makeRule(
      id: value.id,
      name: value.name,
      enforcement: value.enforcement,
      hint: value.hint,
      location: value.location,
      excludingSubtrees: excluded
    ) {
      _ = try await runtimeContext?.resolvedEnvironment()
      return try await findings(
        of: value, indexProvider: indexProvider, excludingSubtrees: excluded
      )
    }
  }

  static func findings(
    of value: RuntimeRule,
    indexProvider: (any RuntimeIndexProvider)?,
    excludingSubtrees: ExcludedSubtrees
  ) async throws -> Rule.Findings {
    try await findings(
      body: value.body,
      at: value.location,
      indexProvider: indexProvider,
      excludingSubtrees: excludingSubtrees
    )
  }

  static func findings(
    body: RuntimeClosure,
    at location: DeclarationLocation,
    indexProvider: (any RuntimeIndexProvider)?,
    excludingSubtrees: ExcludedSubtrees
  ) async throws -> Rule.Findings {
    let evaluator = RuntimeEvaluator(
      globals: body.captures,
      indexProvider: indexProvider,
      excludingSubtrees: excludingSubtrees
    )
    var state = RuntimeEvaluationState(limits: .standard)
    let result: RuntimeValue
    do {
      result = try await evaluator.invoke(
        body,
        arguments: [],
        builder: .checks,
        state: &state
      )
    } catch {
      // The runner tells a cancelled run apart from a failed rule.
      if error.kind == .cancelled { throw CancellationError() }
      throw error
    }
    return try findings(from: result, at: location)
  }

  private static func makeRule(
    id: String,
    name: String,
    enforcement: Enforcement,
    hint: String?,
    location: DeclarationLocation,
    excludingSubtrees: ExcludedSubtrees,
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
        return excludingSubtrees.filteringOffenders(from: findings)
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
