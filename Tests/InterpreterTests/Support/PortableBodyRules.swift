import Bylaws
import Testing

nonisolated let bodyCodebase = Codebase(
  root: .automatic(),
  including: ["Tests/InterpreterTests/Support/BodyRulesSubject.swift"],
  swiftLanguageMode: .v6
)

nonisolated let bodyRules: [Rule] = [
  Rule("secure-connection", "Insecure connections prohibited") {
    try await bodyCodebase.assignments.violations(
      matching: Matcher<SourceAssignment>("enable insecure connections") {
        $0.target.referenceName == "allowsInsecureConnections"
          && $0.value.booleanValue == true
      }
    )
  },
  Rule("secure-initial-values", "URL initial values use HTTPS") {
    try await bodyCodebase.variableBindings.violations(
      matching: Matcher<VariableBinding>("contain an HTTP URL") {
        $0.initialValue?.stringValue?.hasPrefix("http://") ?? false
      }
    )
  },
  Rule("configuration-references", "Configuration references identified") {
    try await bodyCodebase.expressions.violations(
      matching: Matcher<SourceExpression>(
        "refer to the service URL in configure"
      ) {
        $0.referenceName == "serviceURL"
          && $0.enclosingDeclarations.contains { $0.name == "configure" }
      }
    )
  },
]
