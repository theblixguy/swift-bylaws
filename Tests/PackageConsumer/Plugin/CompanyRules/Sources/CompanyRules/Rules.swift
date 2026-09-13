public import Bylaws
import BylawsIndex
import Testing

/// Returns the shared architectural rules for a codebase.
public nonisolated func companyRules(for codebase: Codebase) -> [Rule] {
  companySourceRules(for: codebase) + [
    Rule("company-index", "App entry point belongs to App module") {
      let index = try await codebase.projectIndex(modules: ["App"])
      let definitions = index.definitions(of: "AppEntryPoint")
      return Violations(
        rule: "be defined in App",
        offenders: definitions.filter { $0.module != "App" },
        checkedCount: definitions.count
      )
    },
  ]
}

/// Returns the shared rules that can run before a build.
public nonisolated func companySourceRules(for codebase: Codebase) -> [Rule] {
  let matcher = Matcher<Class>("be final") { isFinal($0) }
  return [
    Rule("company-final-classes", "Classes are final") {
      try await codebase.classes.violations(of: matcher)
    },
  ]
}
