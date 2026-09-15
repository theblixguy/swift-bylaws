import Bylaws
import Testing

func securityRules(_ codebase: Codebase) -> [Rule] {
  [
    Rule("logging-boundary", "System logging confined to logging code") {
      try await codebase.expressions.outside("Sources/Logging").violations(
        matching: Matcher<SourceExpression>("use a system logging API") {
          ["print", "debugPrint", "NSLog", "os_log", "Logger", "OSLog"]
            .contains($0.referenceName ?? "")
        }
      )
    },
    Rule("log-privacy", "Explicit public log values prohibited") {
      try await codebase.expressions.violations(
        matching: Matcher<SourceExpression>(
          "mark an interpolated value public"
        ) {
          $0.interpolations.contains { arguments in
            arguments.contains {
              $0.label == "privacy" && $0.expression.referenceName == "public"
            }
          }
        }
      )
    },
    Rule("keychain-boundary", "Keychain calls confined to keychain code") {
      try await codebase.expressions.outside("Sources/Security/Keychain")
        .violations(
          matching: Matcher<SourceExpression>("use a keychain API") {
            [
              "SecItemAdd",
              "SecItemCopyMatching",
              "SecItemUpdate",
              "SecItemDelete",
            ]
            .contains($0.referenceName ?? "")
          }
        )
    },
    Rule(
      "keychain-accessibility",
      "Deprecated keychain accessibility prohibited"
    ) {
      try await codebase.expressions.violations(
        matching: Matcher<SourceExpression>(
          "use deprecated keychain accessibility"
        ) {
          ["kSecAttrAccessibleAlways", "kSecAttrAccessibleAlwaysThisDeviceOnly"]
            .contains($0.referenceName ?? "")
        }
      )
    },
    Rule(
      "authentication-boundary",
      "Authentication handling confined to networking code"
    ) {
      try await codebase.functions.outside("Sources/Networking/Authentication")
        .violations(
          matching: Matcher<Function>("handle an authentication challenge") {
            $0.parameters
              .contains { $0.type.references("URLAuthenticationChallenge") }
          }
        )
      try await codebase.expressions
        .outside("Sources/Networking/Authentication").violations(
          matching: Matcher<SourceExpression>("use a credential or trust API") {
            [
              "URLCredential",
              "SecTrustSetExceptions",
              "SecTrustSetAnchorCertificates",
              "SecTrustEvaluate",
              "SecTrustEvaluateWithError",
            ]
            .contains($0.referenceName ?? "")
          }
        )
    },
    Rule("https-literals", "URL literals use HTTPS") {
      try await codebase.expressions.violations(
        matching: Matcher<SourceExpression>(
          "contain an HTTP URL outside the debug exception"
        ) {
          guard let url = $0.stringValue?.lowercased() else { return false }
          let isLocalDebugURL = url == "http://127.0.0.1:8080"
            && $0.compilationBranches.contains { $0.condition == "DEBUG" }
          return url.hasPrefix("http://") && !isLocalDebugURL
        }
      )
    },
    Rule("debug-settings", "Insecure connection settings confined to DEBUG") {
      try await codebase.assignments.violations(
        matching: Matcher<SourceAssignment>(
          "enable insecure connections outside DEBUG"
        ) {
          $0.target.referenceName == "allowsInsecureConnections"
            && $0.value.booleanValue == true
            && !$0.compilationBranches.contains { $0.condition == "DEBUG" }
        }
      )
      try await codebase.variableBindings.violations(
        matching: Matcher<VariableBinding>(
          "enable insecure connections outside DEBUG"
        ) {
          $0.name == "allowsInsecureConnections"
            && $0.initialValue?.booleanValue == true
            && !$0.compilationBranches.contains { $0.condition == "DEBUG" }
        }
      )
    },
  ]
}
