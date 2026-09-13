public import Bylaws
import Testing

/// Returns the portable rules for a codebase.
public nonisolated func portableModuleRules(
  for codebase: Codebase
) -> [Rule] {
  let matcher = Matcher<Class>("declare at most one function") {
    internalHasAtMostOneFunction($0)
  }
  return [
    Rule("portable-module", "Classes stay small") {
      try await codebase.classes.violations(of: matcher)
    },
  ]
}

/// Rules exported directly from the test module.
public nonisolated let portableBindingRules: [Rule] = [
  Rule("portable-binding") {
    Violations<Class>(rule: "match", offenders: [], checkedCount: 0)
  },
]
