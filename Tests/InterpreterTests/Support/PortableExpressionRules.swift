import Bylaws
import Testing

nonisolated let expressionCodebase = Codebase(
  root: .automatic(),
  including: ["Tests/InterpreterTests/Support/ExpressionRulesSubject.swift"],
  swiftLanguageMode: .v6
)

nonisolated let expressionRules: [Rule] = [
  Rule("literal-locations", "HTTP literals reported at expression") {
    try await expressionCodebase.expressions
      .violations(matching: Matcher<SourceExpression>("contain an HTTP URL") {
        $0.stringValue?.hasPrefix("http://") ?? false
      })
  },
  Rule("log-privacy", "Public log values reviewed") {
    try await expressionCodebase.calls
      .violations(
        matching: Matcher<FunctionCall>("contain public log values") { call in
          call.arguments.contains { argument in
            argument.expression?.interpolations.contains { interpolation in
              interpolation.contains { value in
                value.label == "privacy" && value.expression.referenceName == "public"
                  && value.expression.referenceLocation?.line == call.location
                  .line
                  && value.expression.referenceLocation?.column != value
                  .expression.location.column
              }
            } ?? false
          }
        }
      )
  },
  Rule("literal-urls", "Service URLs use HTTPS") {
    try await expressionCodebase.calls
      .violations(
        matching: Matcher<FunctionCall>("contain an HTTP URL") { call in
          call.arguments.contains { argument in
            argument.expression?.stringValue?.hasPrefix("http://") ?? false
          }
        }
      )
  },
]
