# Correcting source

Attach source replacements to a rule and apply them with the CLI.

## Overview

You can add a correction to the violations from a `Codebase` query with
`withFix`. The same API works in a portable `Bylaws.swift` rule and in a
Swift Testing rule. A normal lint run or test reports the violations and keeps
the source files unchanged.

The CLI applies corrections when you run `bylaws lint --autocorrect`, then runs
the rules again and reports the result.

## Define a correction

You can use this portable rule to change lowercase hexadecimal digits to
uppercase. Save it as `Bylaws.swift`:

```swift
import Bylaws
import Testing

nonisolated let app = Codebase(
  root: .automatic(),
  including: ["Sources/**"]
)

nonisolated let rules: [Rule] = [
  Rule("hex-digits", "Hexadecimal digits use uppercase") {
    try await app.syntaxNodes(of: .integerLiteral)
      .violations(matching: Matcher<SourceNode>("contain lowercase hex digits") {
        $0.text.hasPrefix("0x") && $0.text.contains(/[a-f]+/)
      })
      .withFix { context in
        for part in try context.source.matches(of: /[a-f]+/) {
          part.replacement(with: part.text.uppercased())
        }
      }
  },
]
```

For `0xdead_Beef`, the rule replaces the matching letters and produces
`0xDEAD_BEEF`. The prefix, underscore and surrounding source keep their original
bytes. Each match identifies the source to replace, so you do not have to
calculate a range from the diagnostic.

The fix closure runs once for each offender. You can write individual edits,
edit arrays, `if` and `for` statements in its result builder.
All edits for one offender form one correction, including edits in several
files. An empty result leaves that offender without a correction.

If you want to give the correction a title, use
`.withFix("Use uppercase hex digits") { ... }`.

## Choose the source to replace

You can access the checked model through `context.offender` and use its source
properties to select the part of the code to replace:

| API | Source available |
| --- | --- |
| `context.source` | The offender's source. Declarations exclude surrounding comments and whitespace. A `SourceFile` includes the complete file. |
| `context.file` | The whole captured file, including comments and whitespace. |
| `context.codebase` | The codebase that produced the selection, available for further queries. |
| `declaration.nameSource` | The declaration's name. |
| `declaration.bodySource` | The contents of the body, excluding its outer braces. |
| `call.calledExpressionSource` | The expression that the call invokes. |
| `call.memberNameSource` | The called member's name. |
| `argument.expressionSource` | The argument's expression. |
| `argument.labelSource` | The argument's label, when present. |

A source property throws when the model has no corresponding source. For
example, a function requirement has no body. Manually constructed or decoded
declarations have no editable source, so use declarations returned by a
`Codebase` query.

You can select a call argument with `try call.argument(labeled: "value")`.
It throws when the label identifies zero arguments or several arguments.
`source.matches(of: regex)` returns the complete matches as source slices. Use
`try matches.only()` when the correction must have exactly one target.

For a range that you calculate yourself, `try source.slice(0..<4)` uses UTF-8
offsets relative to that slice. It checks the bounds and rejects a range that
splits a Unicode scalar. You can use `.file` to read the whole file from any
slice, regardless of the depth of the queried model.

## Query another file

You can query `context.codebase` to find code in other files selected by the
rule. This example renames a known pair of class declarations:

```swift
Rule("paired-names") {
  try await app.classes.named("Primary")
    .violations(matching: Matcher<Class>("use the current name") { _ in true })
    .withFix("Rename paired classes") { context in
      let companions = try await context.codebase.classes.named("Companion")
      let companion = try companions.only()
      try context.offender.nameSource.replacement(with: "Main")
      try companion.nameSource.replacement(with: "Helper")
    }
}
```

The two edits belong to one correction even when the declarations are in
different files. `only()` throws if the query finds no companion or several
companions. This example changes declaration names only. A rename that also
changes references must select and replace those references explicitly.

The codebase retains its root, inclusion patterns and exclusions. A query can
read all files within that scope, without a fixed line or byte limit. The
available memory limits how much source a run can hold. You can also query
another explicitly configured `Codebase`. Bylaws checks for changes to the
Swift source and supported project configuration read through these queries.
If a fix depends on a separate file read or network request, Bylaws cannot
check whether that input has changed.

## Write a Swift Testing rule

You can construct violations and attach fixes directly in a test. Call
`report()` to make the result available to both Swift Testing and the CLI:

```swift
import Bylaws
import Testing

@Test("Hexadecimal digits use uppercase")
func uppercaseHexDigits() async throws {
  let app = Codebase(root: .automatic(), including: ["Sources/**"])
  let violations = try await app.syntaxNodes(of: .integerLiteral)
    .violations(matching: Matcher<SourceNode>("contain lowercase hex digits") {
      $0.text.hasPrefix("0x") && $0.text.contains(/[a-f]+/)
    })
    .withFix { context in
      for part in try context.source.matches(of: /[a-f]+/) {
        part.replacement(with: part.text.uppercased())
      }
    }

  violations.report()
}
```

By default, `report()` uses the test function's identity as the rule ID for
CLI selection and baselines. If a test reports several checks, give each a
distinct ID with `report(ruleID:)`. An ordinary `#expect` can report a test
failure, but corrections must be attached to violations passed to `report()`.

You can also keep portable rules in `Bylaws.swift` and run them through
`Rule.discovered()`, as shown in
<doc:RunningRulesFromTheCLI#Run-a-rules-file-as-tests>. Calling
`try await rule.report()` retains their corrections. The CLI recognises the
same discovered rule when it also runs the test, so it applies that rule's
corrections once. A separately defined Swift Testing rule must have its own ID.

## Apply and recheck

Run the command from the project root:

```sh
bylaws lint --autocorrect
```

The CLI reads portable rules and runs tests when the root contains a SwiftPM
package with test targets. A build failure or an unrelated test failure in the
first run stops corrections from being applied. Each command applies
corrections once and reports any violations that remain after verification.

If you want to check the proposed corrections and see a patch before applying
them, run:

```sh
bylaws lint --autocorrect --dry-run
```

A dry run keeps the source unchanged and reports the original violations.

### Choose tests and rules

You can choose a test package with `--test-package` and select tests with
`--test-filter`, as described in
<doc:RunningRulesFromTheCLI#Run-Swift-Testing-rules>. Use `--only` and `--skip`
to select rule IDs, or `--skip-tests` to run portable rules alone.

Every edit in a correction must be within the selected `--report-path` values.
The CLI omits corrections for offenders accepted by a baseline.

### Verify test rules

Each Swift Testing check must call `report()` from the same test during
verification, including when it passes. Keep its rule ID, description, hint
and enforcement unchanged. A parameterised test that selects only offenders
can become empty after the correction.
Report the whole check from a test without parameters, or keep the full
selection as test arguments so the corrected cases run again.

If a rule disappears from the second run, the command reports
incomplete verification and lists the changed files. Applied edits remain in
place.

## Use compiler-index queries

Use `Codebase` queries for compiler-index access so the CLI can check that the
index matches the source. Compiler-index corrections build fresh SwiftPM
indexes before applying edits and during verification, which can take longer
than a normal lint run.

On macOS, the command plugin's default sandbox blocks the fresh build for a
compiler-index correction. Run that correction with SwiftPM's
`--disable-sandbox` option:

```sh
swift package --disable-sandbox --allow-writing-to-package-directory \
  bylaws --autocorrect
```

A normal lint run can use index data from an existing build with the default
sandbox.

If you want to limit rules to source queries, use `--source-only`.

This option rejects `Codebase` index queries in both portable and Swift Testing
rules. The CLI builds and runs tests with either setting.

A Swift Testing rule must use the test package root for compiler-index
queries. Source queries can read other configured roots.

The CLI can build fresh indexes for SwiftPM packages. It cannot verify the
freshness of an existing Xcode or custom index for a correction. An index
describes only the targets and build configuration that produced it.

## Correction checks and limits

Bylaws stops if a checked source or configuration input changes during the
run. Adding or removing a source file also counts as a change. A failed
`Codebase` query prevents corrections even if the rule catches the error.

Corrections target existing, writable `.swift` files under the lint root.
The CLI protects active portable rule and configuration files and all source
files in the test package's test targets. The report output must also be
separate from source and configuration inputs.
Symbolic links and hard links cannot be correction targets. File creation,
deletion and moves are outside the correction API.

An imported library can contain both application code and rule helpers,
so the CLI cannot identify its helpers for protection automatically. Keep
matcher and fix helpers in test targets when they must be protected.

The CLI combines equal replacements. If replacements overlap, it rejects
every correction involved in the conflict, including other edits in a
correction that spans several files. Independent corrections can proceed.
The CLI parses each proposed file with its captured Swift language mode and
rejects a correction that produces syntax errors. Every rule that proposes
corrections for a file must use the same `swiftLanguageMode`.

Syntax validation gives no guarantee that the corrected program type-checks
or preserves its behaviour. A source replacement also has no automatic symbol
rename or formatting step. The rule author must choose the target and the
replacement text. The final rule run checks the rules that you selected.

A write or verification failure can leave some files changed, and the error
lists those paths. Review the changes and run the project's build and tests
after a correction.

### Portable rule limits

Portable rules support the fix builder, source projections and single-line
Swift regex literals, including raw delimiters such as `#/usr/local/#`.
Multiline regex literals and regex capture APIs are outside the portable
subset. Portable matcher and collection callbacks are synchronous and
nonthrowing. The fix closure can query a codebase asynchronously and use a
loop for throwing source projections. A portable rule also has interpreter
instruction and call-depth limits, so a large edit loop can stop with an
execution-limit error.

The CLI evaluates top-level bindings before an individual rule's override
scope applies. Keep queries and fixes that depend on that scope inside the
rule body or a helper called from it. See
<doc:RunningRulesFromTheCLI#Discovery-and-overrides> for the override rules.

A Swift Testing rule can use the full Swift language. Its replacements must
use the same correction API to identify the captured source to change.
