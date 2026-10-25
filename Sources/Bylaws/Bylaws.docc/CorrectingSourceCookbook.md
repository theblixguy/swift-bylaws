# Correction cookbook

Write corrections that change selected text, tokens or comments and apply them
through the CLI.

## Overview

Each recipe has a complete rule for `Bylaws.swift` and Swift Testing. Choose
one version to use in your project. A normal run reports violations. Use
`bylaws lint --autocorrect --dry-run` to review proposed corrections, then
`bylaws lint --autocorrect` to apply them and rerun the rules.

Start with a small source replacement, then use tokens and trivia when the
rule must distinguish code from comments or strings. <doc:CorrectingSource>
explains source scope, correction checks and CLI options.
<doc:FormattingCookbook> covers layouts and ordering.

## Change part of a literal

This rule changes lowercase letters in hexadecimal integer literals. The match
identifies the letters to replace, which keeps the prefix, separators and
surrounding code unchanged.

### Bylaws.swift

```swift
import Bylaws

nonisolated let app = Codebase(root: .automatic(), including: ["Sources/**"])

nonisolated let rules: [Rule] = [
  Rule("uppercase-hex-digits", "Hexadecimal digits use uppercase") {
    try await app.syntaxNodes(of: .integerLiteral)
      .violations("Hexadecimal digits use uppercase") { literal in
        if literal.text.hasPrefix("0x") {
          for letters in try literal.source.matches(of: /[a-f]+/) {
            letters.replacement(with: letters.text.uppercased())
          }
        }
      }
  },
]
```

### Swift Testing

```swift
import Bylaws
import Testing

@Test("Hexadecimal digits use uppercase")
func uppercaseHexDigits() async throws {
  let app = Codebase(root: .automatic(), including: ["Sources/**"])
  let violations = try await app.syntaxNodes(of: .integerLiteral)
    .violations("Hexadecimal digits use uppercase") { literal in
      if literal.text.hasPrefix("0x") {
        for letters in try literal.source.matches(of: /[a-f]+/) {
          letters.replacement(with: letters.text.uppercased())
        }
      }
    }

  violations.report(ruleID: "uppercase-hex-digits")
}
```

For `0xdead_Beef`, the result is `0xDEAD_BEEF`. Decimal literals, comment text
and string contents remain outside the selection. A literal whose letters
are uppercase produces no violation.

## Space a binary operator

This rule puts one space on each side of a binary `+` in
`Sources/Math`. It distinguishes the operator token from a unary `+`, a
comment or a string. The policy keeps existing line breaks.

### Bylaws.swift

```swift
import Bylaws

nonisolated let app = Codebase(
  root: .automatic(),
  including: ["Sources/Math/**"]
)

nonisolated let rules: [Rule] = [
  Rule("binary-plus-spacing", "Binary plus uses one space") {
    try await app.files.violations("Binary plus uses one space") { file in
      for token in try file.tokens {
        if token.kind == .binaryOperator, token.text == "+" {
          let spacing = try token.spacing
          if !spacing.before.text.contains("\n"),
             !spacing.before.text.contains("\r"),
             !spacing.after.text.contains("\n"),
             !spacing.after.text.contains("\r")
          {
            try spacing.before.replacement(with: .space)
            try spacing.after.replacement(with: .space)
          }
        }
      }
    }
  },
]
```

### Swift Testing

```swift
import Bylaws
import Testing

@Test("Binary plus uses one space")
func binaryPlusSpacing() async throws {
  let app = Codebase(root: .automatic(), including: ["Sources/Math/**"])
  let violations = try await app.files
    .violations("Binary plus uses one space") { file in
      for token in try file.tokens {
        if token.kind == .binaryOperator, token.text == "+" {
          let spacing = try token.spacing
          if !spacing.before.text.contains("\n"),
             !spacing.before.text.contains("\r"),
             !spacing.after.text.contains("\n"),
             !spacing.after.text.contains("\r")
          {
            try spacing.before.replacement(with: .space)
            try spacing.after.replacement(with: .space)
          }
        }
      }
    }

  violations.report(ruleID: "binary-plus-spacing")
}
```

The rule applies to every binary `+` in the selected files, including
overloaded operators.

## Change a comment marker

This rule replaces `FIXME` with the project's `TODO` marker in ordinary line
comments. It leaves documentation comments, block comments and string literals
unchanged.

### Bylaws.swift

```swift
import Bylaws

nonisolated let app = Codebase(root: .automatic(), including: ["Sources/**"])

nonisolated let rules: [Rule] = [
  Rule("comment-markers", "Line comments use TODO") {
    try await app.files.violations("Line comments use TODO") { file in
      for comment in try file.trivia {
        if comment.kind == .lineComment {
          for marker in comment.source.matches(of: /\bFIXME\b/) {
            marker.replacement(with: "TODO")
          }
        }
      }
    }
  },
]
```

### Swift Testing

```swift
import Bylaws
import Testing

@Test("Line comments use TODO")
func commentMarkers() async throws {
  let app = Codebase(root: .automatic(), including: ["Sources/**"])
  let violations = try await app.files
    .violations("Line comments use TODO") { file in
      for comment in try file.trivia {
        if comment.kind == .lineComment {
          for marker in comment.source.matches(of: /\bFIXME\b/) {
            marker.replacement(with: "TODO")
          }
        }
      }
    }

  violations.report(ruleID: "comment-markers")
}
```

Use a precise match when a comment can contain source examples or identifiers
that must retain their spelling.

## Change a declaration and a related file

This rule renames `LegacyScreen` to `AccountScreen` and updates its registration
in `Sources/Registry.swift`. It checks that the file contains exactly one
string literal with the old name before proposing either edit.

### Bylaws.swift

```swift
import Bylaws

nonisolated let app = Codebase(root: .automatic(), including: ["Sources/**"])

nonisolated let rules: [Rule] = [
  Rule("registered-screen-name", "Registered screen uses current name") {
    try await app.classes.named("LegacyScreen")
      .violations("Registered screen uses current name") { declaration in
        let registrations = try await app.syntaxNodes(of: .stringLiteral)
          .filter {
            $0.location.filePath.hasSuffix("/Sources/Registry.swift")
              && $0.expression?.stringValue == "LegacyScreen"
          }
        let registration = try registrations.only()
        try declaration.nameSource.replacement(with: "AccountScreen")
        try registration.source.replacement(with: "\"AccountScreen\"")
      }
  },
]
```

### Swift Testing

```swift
import Bylaws
import Testing

@Test("Registered screen uses current name")
func registeredScreenName() async throws {
  let app = Codebase(root: .automatic(), including: ["Sources/**"])
  let violations = try await app.classes.named("LegacyScreen")
    .violations("Registered screen uses current name") { declaration in
      let registrations = try await app.syntaxNodes(of: .stringLiteral)
        .filter {
          $0.location.filePath.hasSuffix("/Sources/Registry.swift")
            && $0.expression?.stringValue == "LegacyScreen"
        }
      let registration = try registrations.only()
      try declaration.nameSource.replacement(with: "AccountScreen")
      try registration.source.replacement(with: "\"AccountScreen\"")
    }

  violations.report(ruleID: "registered-screen-name")
}
```

Both edits form one correction, even when the source is in two files. In a
project with several registration strings, narrow the second query by path or
enclosing declaration before calling `only()`.

This example updates the named declaration and registration string. References
to the type need their own source selections. A compiler-index rule can
resolve some references, subject to the build and index limits in
<doc:CorrectingSource#Use-compiler-index-queries>.

## Test the correction

Test the corrected source as well as the reported violation. This test checks
the exact output and runs the same rule against the corrected source. It
combines the edits in memory so it can check the result without changing files.

```swift
import Bylaws
import Testing

@Test("Hex correction preserves other source and passes on second run")
func hexCorrectionResult() async throws {
  func check(_ app: Codebase) async throws -> Violations<SourceNode> {
    try await app.syntaxNodes(of: .integerLiteral)
      .violations("Hexadecimal digits use uppercase") { literal in
        if literal.text.hasPrefix("0x") {
          for letters in try literal.source.matches(of: /[a-f]+/) {
            letters.replacement(with: letters.text.uppercased())
          }
        }
      }
  }

  let original = "let mask = 0xdead_Beef"
  let app = Codebase(root: .sources(["Mask.swift": original]))
  let violations = try await check(app)
  let fix = try #require(violations.fixes.first ?? nil)
  let file = try await app.files.only()
  let result = try file.source.replacement(applying: fix.edits)

  #expect(result.replacement == "let mask = 0xDEAD_BEEF")
  let corrected = Codebase(root: .sources(["Mask.swift": result.replacement]))
  let verified = try await check(corrected)
  #expect(verified.isEmpty)
}
```

You can also check that a layout rejects an omitted attribute:

```swift
import Bylaws
import Testing

@Test("Attribute layout rejects omitted source")
func omittedAttribute() async throws {
  let app = Codebase(root: .sources([
    "Screen.swift": "@MainActor @Observable class Screen {}",
  ]))
  let declaration = try await app.classes.only()
  let attributes = declaration.attributes

  #expect(throws: SourceLayoutReplacementError.missingElement) {
    try attributes.replacement {
      Line { attributes[0] }
    }
  }
}
```

Test source that your rule should change and source that it should preserve.
Include comments, Unicode, line endings and multiline strings when the rule
can change them. A successful syntax check cannot establish that a correction
preserves program behaviour.
