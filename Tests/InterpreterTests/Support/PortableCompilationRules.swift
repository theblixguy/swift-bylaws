import Bylaws
import Testing

nonisolated let compilationCodebase = Codebase(
  root: .automatic(),
  including: ["Tests/InterpreterTests/Support/CompilationRulesSubject.swift"],
  swiftLanguageMode: .v6
)

nonisolated let compilationRules: [Rule] = [
  Rule("debug-settings", "Insecure connection settings confined to DEBUG") {
    try await compilationCodebase.assignments.violations(
      matching: Matcher<SourceAssignment>(
        "enable insecure connections outside DEBUG"
      ) {
        $0.target.referenceName == "allowsInsecureConnections"
          && $0.value.booleanValue == true
          && !$0.compilationBranches.contains { $0.condition == "DEBUG" }
      }
    )
  },
  Rule("debug-types", "Debug types confined to DEBUG") {
    try await compilationCodebase.files.violations(
      matching: Matcher<SourceFile>("declare debug types outside DEBUG") { file in
        let branches = file.compilationBranches
        return file.structs.contains { declaration in
          declaration.name.hasPrefix("Debug")
            && !branches.contains { branch in
              branch.condition == "DEBUG" && branch
                .contains(declaration.location)
            }
        }
      }
    )
  },
  Rule("else-branches", "Else branches identified after DEBUG") {
    try await compilationCodebase.compilationBranches.violations(
      matching: Matcher<CompilationBranch>("follow DEBUG without a condition") {
        $0.condition == nil && $0.precedingConditions.contains("DEBUG")
      }
    )
  },
]
