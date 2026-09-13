import Bylaws
import Testing

nonisolated let portableRulesCodebase = Codebase(
  root: .automatic(),
  including: ["Tests/InterpreterTests/Support/PortableRulesSubject.swift"]
)

nonisolated func hasAtMostOnePortableFunction(
  _ declaration: Class
) -> Bool {
  declaration.functions.count <= 1
    && declaration.functions.allSatisfy {
      $0.cyclomaticComplexity <= 1
    }
    && declaration.genericParameters.isEmpty
    && declaration.sourceRange.count > 0
}

nonisolated let portableRulesMatcher =
  Matcher<Class>("declare at most one function") {
    hasAtMostOnePortableFunction($0)
  }

nonisolated let portableRules: [Rule] = [
  Rule("portable-parity", "Portable rules stay small") {
    try await portableRulesCodebase.classes.violations(
      of: portableRulesMatcher
    )
  },
]
