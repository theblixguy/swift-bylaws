# Inspecting expressions

Check literal values, member references and call arguments in Swift code.

## Check literal values

You can use `codebase.expressions` to check values written in your Swift files,
including local variables and closures. For example, this rule reports HTTP
string literals in the networking folder:

```swift
import Bylaws

let codebase = Codebase(including: ["Sources/Networking/**"])

let rules: [Rule] = [
  Rule("https-literals", "Networking URL literals use HTTPS") {
    try await codebase.expressions.violations(
      matching: Matcher<SourceExpression>("contain an HTTP URL") {
        $0.stringValue?.hasPrefix("http://") ?? false
      }
    )
  },
]
```

The rule reports `"http://example.com"` at the string's position and also
checks raw strings, multiline strings and escaped characters. For a reference
such as `serviceURL`, `stringValue` returns `nil`. You can test the value of
that variable at runtime in a separate test.

You can run this rule through the CLI or Swift Testing to check every `#if`
branch, including code for other build configurations.

## Inspect a call argument

You can inspect a call argument through its `expression` property. Each access
parses the argument, so save the expression in a local variable when you want
to check several of its properties.

Use `stringValue`, `booleanValue`, `integerValue` or `floatingPointValue` to
read a literal's value. For example, `booleanValue` returns `false` for the
literal `false` and `nil` for a variable such as `isEnabled`. You can check
for the `nil` literal with `isNilLiteral`.

`referenceName` gives you the identifier or member name from the source. For
example, `Settings.public` has the name `public` and a `base` expression named
`Settings`. Its `referenceLocation` points to the `public` token, while
`location` points to the start of `Settings.public`. Both reference properties
return `nil` for expressions other than identifiers and member references.
To check which symbol a name refers to, you can use the compiler index after
a build.

## Inspect nested values

You can read the elements of an array literal through `arrayElements` or get
each key-value pair in a dictionary literal through `dictionaryElements`.
The elements are in source order, including repeated dictionary keys, and each
property returns `nil` for other expressions.

A string's `interpolations` property contains an argument list for each
interpolation. In `"User: \(user, privacy: .public)"`, the first argument is
`user` and the argument labelled `privacy` has the member name `public`.
The plain string `"privacy: .public"` has no interpolation arguments, so you
can check the privacy setting without matching those words in log text.

Use <doc:AdvancedRules> when you need SwiftSyntax access beyond these
properties.
