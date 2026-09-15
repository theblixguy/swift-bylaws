# Security rules

Check security-related code against your project's policies.

## Choose what to enforce

You can use Bylaws to keep sensitive operations in reviewed code, prohibit
particular API uses and check literal settings alongside your security review
and runtime tests. The rules check the source you select. To trace data through
the program or check third-party packages for vulnerabilities, you need other
security tools.

Add the `Rule` values below to your rules array. Each example uses this
codebase, which you can change to match your project's source folders:

```swift
import Bylaws

let codebase = Codebase(including: ["Sources/**"])
```

The rules run through Swift Testing or the CLI. See <doc:GettingStarted> for
setup and <doc:RuleAdoption> for testing a rule before you enforce it.

## Keep system logging in one folder

You can direct logging through a project-owned wrapper and review how that
wrapper handles user data. This rule reports references to the listed logging
APIs outside `Sources/Logging`, including references stored for a later call:

```swift
Rule("logging-boundary", "System logging confined to logging code") {
  try await codebase.expressions.outside("Sources/Logging").violations(
    matching: Matcher<SourceExpression>("use a system logging API") {
      ["print", "debugPrint", "NSLog", "os_log", "Logger", "OSLog"]
        .contains($0.referenceName ?? "")
    }
  )
}
```

A `Logger()` reference in `Sources/Logging/Log.swift` passes, while a
`Swift.print(token)` call in a feature file fails. Other files can call your
wrapper's methods.

You can extend the list with other logging APIs your project uses. The rule
matches names, so a project declaration called `Logger` also matches. Use a
compiler-index rule if you need to check which declaration a name refers to.
OWASP's [logging guidance] explains the risks of recording sensitive data.

## Review public log values

Apple's [log privacy options] control which interpolated values appear in
logs. You can prohibit explicit `privacy: .public` arguments with this rule:

```swift
Rule("log-privacy", "Explicit public log values prohibited") {
  try await codebase.expressions.violations(
    matching: Matcher<SourceExpression>("mark an interpolated value public") {
      $0.interpolations.contains { arguments in
        arguments.contains {
          $0.label == "privacy" && $0.expression.referenceName == "public"
        }
      }
    }
  )
}
```

The rule reports `logger.info("User: \(user, privacy: .public)")` and permits
the same message with `.private`. It checks interpolation arguments, so the
plain string `"privacy: .public"` also passes.

The rule checks explicit privacy arguments in string interpolation, including
custom interpolation types that use the same label. You need to review which
values contain sensitive data and how your logging wrapper handles them.
When the privacy argument is omitted, the default depends on the value's type,
as described in Apple's [logging guide].

## Keep keychain access in one folder

You can keep keychain operations in `Sources/Security/Keychain` and expose
project-specific operations such as saving an account token:

```swift
Rule("keychain-boundary", "Keychain calls confined to keychain code") {
  try await codebase.expressions.outside("Sources/Security/Keychain").violations(
    matching: Matcher<SourceExpression>("use a keychain API") {
      ["SecItemAdd", "SecItemCopyMatching", "SecItemUpdate", "SecItemDelete"]
        .contains($0.referenceName ?? "")
    }
  )
}
```

`SecItemAdd(attributes, nil)` passes in the keychain folder and fails in a
feature folder, including calls inside local functions and closures.

You can then review the wrapper's item attributes and error handling and test
that its operations store the correct data.

## Prohibit deprecated keychain accessibility options

Apple marks [`kSecAttrAccessibleAlways`][always-accessible] and
[`kSecAttrAccessibleAlwaysThisDeviceOnly`][always-accessible-device] as
deprecated. This rule reports their use even inside the keychain wrapper:

```swift
Rule("keychain-accessibility", "Deprecated keychain accessibility prohibited") {
  try await codebase.expressions.violations(
    matching: Matcher<SourceExpression>("use deprecated keychain accessibility") {
      ["kSecAttrAccessibleAlways", "kSecAttrAccessibleAlwaysThisDeviceOnly"]
        .contains($0.referenceName ?? "")
    }
  )
}
```

A dictionary entry such as `kSecAttrAccessible: kSecAttrAccessibleAlways`
fails, while `kSecAttrAccessibleWhenUnlocked` passes this check. You can choose
an option based on when your app needs access to the item, as explained in
Apple's [keychain accessibility guide]. The rule checks references to the
constants, so their names can appear in string literals without a violation.

## Keep authentication handling in reviewed networking code

You can keep functions that take an authentication challenge and direct uses
of credential or trust APIs in `Sources/Networking/Authentication`:

```swift
Rule("authentication-boundary", "Authentication handling confined to networking code") {
  try await codebase.functions.outside("Sources/Networking/Authentication").violations(
    matching: Matcher<Function>("handle an authentication challenge") {
      $0.parameters.contains { $0.type.references("URLAuthenticationChallenge") }
    }
  )
  try await codebase.expressions.outside("Sources/Networking/Authentication").violations(
    matching: Matcher<SourceExpression>("use a credential or trust API") {
      ["URLCredential", "SecTrustSetExceptions", "SecTrustSetAnchorCertificates",
       "SecTrustEvaluate", "SecTrustEvaluateWithError"]
        .contains($0.referenceName ?? "")
    }
  )
}
```

A delegate method with a `URLAuthenticationChallenge` parameter fails outside
that folder, as does a `URLCredential(trust: trust)` expression. References to
`URLCredential` for other authentication methods also match, so change the
selection if your project keeps that code elsewhere.

Apple recommends [default server trust handling] for most apps. If your app
uses a custom handler, review its certificate and host validation and test
its failure paths. The rule matches type and API names in the source, so you
need separate checks for aliases and calls through a project wrapper.

## Check HTTP URL literals

You can report HTTP string literals and permit one development endpoint only
inside a `DEBUG` branch:

```swift
Rule("https-literals", "URL literals use HTTPS") {
  try await codebase.expressions.violations(
    matching: Matcher<SourceExpression>("contain an HTTP URL outside the debug exception") {
      guard let url = $0.stringValue?.lowercased() else { return false }
      let isLocalDebugURL = url == "http://127.0.0.1:8080"
        && $0.compilationBranches.contains { $0.condition == "DEBUG" }
      return url.hasPrefix("http://") && !isLocalDebugURL
    }
  )
}
```

The rule reports `"HTTP://example.com"` and permits `"https://example.com"`
anywhere. You can also use `"http://127.0.0.1:8080"` inside `#if DEBUG`, with
a case-insensitive comparison of the complete address. Changing the host,
adding credentials or moving this development URL into the `#else` branch
causes a violation.

The rule checks decoded string literals, including raw strings and escaped
characters. For URLs assembled through interpolation, concatenation or runtime
input, you need to validate the complete URL separately. Runtime tests also
need to cover redirects and server trust, including for HTTPS literals.

## Check debug-only settings

You can check both assignments and initial values of a project-defined
setting. This example permits a literal `true` for
`allowsInsecureConnections` only inside a branch whose condition is `DEBUG`:

```swift
Rule("debug-settings", "Insecure connection settings confined to DEBUG") {
  try await codebase.assignments.violations(
    matching: Matcher<SourceAssignment>("enable insecure connections outside DEBUG") {
      $0.target.referenceName == "allowsInsecureConnections"
        && $0.value.booleanValue == true
        && !$0.compilationBranches.contains { $0.condition == "DEBUG" }
    }
  )
  try await codebase.variableBindings.violations(
    matching: Matcher<VariableBinding>("enable insecure connections outside DEBUG") {
      $0.name == "allowsInsecureConnections"
        && $0.initialValue?.booleanValue == true
        && !$0.compilationBranches.contains { $0.condition == "DEBUG" }
    }
  )
}
```

The rule reports an assignment or initial value of `true` outside a `DEBUG`
branch and permits `false` anywhere. An expression such as
`allowsInsecureConnections = settings.isEnabled` also passes because the rule
checks for the literal `true`. You need a separate test for the value of
`settings.isEnabled` at runtime.

Keep `DEBUG` out of release build settings. <doc:ConditionalCompilation>
explains the source context and how `#elseif` and `#else` affect a branch.

## Keep exceptions specific

Use a path exception for the code that owns an operation, rather than
excluding an entire feature. Where an exception depends on a build condition,
check that condition as well as the value or path.

Test each rule against code that should pass and code that should fail,
including the exception's boundaries. For an existing codebase, you can start
with an advisory rule or a baseline as described in <doc:RuleAdoption>.

[logging guidance]: https://mas.owasp.org/MASWE/MASVS-STORAGE/MASWE-0005/
[log privacy options]: https://developer.apple.com/documentation/os/oslogprivacy
[logging guide]: https://developer.apple.com/documentation/os/generating-log-messages-from-your-code
[keychain accessibility guide]: https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility
[always-accessible]: https://developer.apple.com/documentation/security/ksecattraccessiblealways
[always-accessible-device]: https://developer.apple.com/documentation/security/ksecattraccessiblealwaysthisdeviceonly
[default server trust handling]: https://developer.apple.com/documentation/foundation/performing-manual-server-trust-authentication
