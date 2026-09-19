# Adopting rules

Introduce, test and share architectural rules.

## Overview

You can start with an advisory rule and enforce it after fixing the violations.
If the rule must reject new violations immediately, use a baseline to record
the existing ones.

The Swift Testing examples use `Codebase.app` from <doc:GettingStarted> and
the `Bylaws` and `Testing` imports.

## Advisory rules

You can add `.advisory` to a suite to see its issues without failing the test
run while you fix the existing violations:

```swift
@Suite("Style advisories", .advisory)
struct StyleAdvisories {
  @Test("Classes are final", arguments: try await Codebase.app.classes)
  func isFinal(_ aClass: Class) {
    #expect(aClass.isFinal, sourceLocation: aClass.testingLocation)
  }
}
```

Swift 6.2 displays advisory issues as known issues, while Swift 6.3 and later
display them as warnings. Baselined violations use the same display format.

## Explain the rule and its fix

A rule's name states the condition that the code must satisfy. A hint can
explain a fix when the name alone is insufficient. For example, if view models
share loading and error handling through a base class:

```swift
Rule(
  "viewmodel-inheritance",
  "View models inherit from BaseViewModel",
  hint: "Keep shared loading and error handling in BaseViewModel."
) {
  try await Codebase.app.classes.suffixed("ViewModel")
    .excluding("BaseViewModel")
    .violations(of: .inherits(from: "BaseViewModel"))
}
```

If the reason for a rule is not clear from its name, add a short block comment
above it. Add a bad example and a good example when they make the expected
change clearer:

```swift
/*
 Direct console output bypasses the project's logging and redaction policy.

 Bad:
 print(order)

 Good:
 logger.info("Created order")
 */
Rule(
  "no-print",
  "Source files do not call print",
  hint: "use the project's logger or remove the call"
) {
  app.calls.violations(matching: .references("print"))
}
```

The hint appears with violations in tests and CLI output and carries over to an
override unless you supply a different one. CLI reports include the declaration's
file and line, so a coding agent can open the rule and read its examples before
changing the offending code.

## Baselines

A new rule can find hundreds of existing violations. A baseline records them,
so you can enforce the rule immediately and reject each new violation. Start
with an empty baseline in its own file:

```swift
extension Baseline {
  static let app = Baseline("app", entries: [])
}
```

To record the violations, add `.baseline(.app, mode: .record)` to the suite
and run the full suite once. The run rewrites the baseline file and fails,
so CI cannot pass while recording is enabled. Remove `mode: .record`, then run
the suite again. For a `[Rule]` array named `projectRules`, the suite is:

```swift
@Suite("Architecture", .codebase(.app), .baseline(.app))
struct ArchitectureRules {
  @Test("Code follows the architecture rules", arguments: projectRules)
  func architecture(_ rule: Rule) async throws {
    try await rule.report()
  }
}
```

Recorded violations remain visible without failing the run, while new ones
fail. For a parameterised test that checks declarations directly, add
`.annotatesViolations` to identify the declaration for each baseline entry:

```swift
@Test(
  "Screen view models are final",
  .annotatesViolations,
  arguments: try await Codebase.app.classes.suffixed("ViewModel")
)
func isFinal(_ viewModel: Class) {
  #expect(viewModel.isFinal)
}
```

Once a `Rule` completes, Bylaws reports any baseline entries whose violations
are no longer present and fails the run. Review the fixes and record the
baseline again with a full test run to remove those entries. When checking a
baseline, entries for skipped rules are left unchecked.

For parameterised tests that check declarations directly, review and remove
stale baseline entries manually. Bylaws keeps those entries because the test
run may have selected only some cases. You can use `Rule.report()` to check a
whole rule in one test case and have Bylaws report its stale entries.

Write a small set of permanent exceptions into the rule's own query, where
reviewers can see them:

```swift
arguments: try await Codebase.app.classes
  .suffixed("ViewModel")
  .excluding("PreviewViewModel")
```

## Test your rules

You can test a matcher against short source strings with the `.sources` root.
Include examples that should pass and examples that should fail, such as an
import that crosses a layer boundary:

```swift
@Test("Layering rejects a UI import in Domain")
func domainImportingUI() async throws {
  let codebase = Codebase(root: .sources([
    "Sources/Domain/User.swift": "import UI",
    "Sources/UI/HomeView.swift": "import Domain",
  ]))
  let layering = Layering {
    Layer("Domain", files: ["Sources/Domain/**"])
    Layer("UI", files: ["Sources/UI/**"], mayImport: ["Domain"])
  }
  let result = try await codebase.checkLayering(layering)
  #expect(result.violations.count == 1)
}
```

## Check your test code

A `Codebase` can contain your tests as well as production source. Define a
second codebase for the test files, then use the same queries against it:

```swift
extension Codebase {
  nonisolated static let tests = Codebase(
    root: .automatic(),
    including: ["Tests/**"]
  )
}

@Test("Types marked @Suite are structs")
func suitesAreStructs() async throws {
  let suites = try await Codebase.tests.types.where(.hasAttribute("Suite"))
  #expect(suites.violations(of: .isStruct).isEmpty)
}

@Test("Tests avoid XCTest wait APIs")
func noXCTestWaits() async throws {
  let violations = try await Codebase.tests.functions
    .violations(matching: .calls("XCTWaiter") || .calls("waitForExpectations"))
  #expect(violations.isEmpty)
}
```

You can inspect attribute arguments to check conventions for `@Test` and
`@Suite`. This example looks for a string literal in a test's attribute:

```swift
@Test(
  "Every test has a display name",
  .annotatesViolations,
  arguments: try await Codebase.tests.functions
    .where(.hasAttribute("Test"))
)
func hasDisplayName(_ test: Function) {
  #expect(test.attribute(named: "Test")?.arguments?.contains("\"") == true)
}
```

A string in a trait argument can also satisfy this check. Use a syntax-tree
check if you need to distinguish the display name from other arguments.

You can require each test to contain a direct assertion by checking for
`#expect` or `#require` calls:

```swift
@Test(
  "Tests contain a direct assertion",
  .annotatesViolations,
  arguments: try await Codebase.tests.functions
    .where(.hasAttribute("Test"))
)
func testsAssert(_ test: Function) {
  #expect(test.calls("#expect") || test.calls("#require"))
}
```

Add exceptions for tests that use shared assertion helpers or `Issue.record`.

You can also select files that contain a declaration macro such as `#Preview`.
This rule keeps previews in a separate target:

```swift
@Test("Previews live in the preview target")
func previewsAreContained() async throws {
  let violations = try await Codebase.app.files
    .outside("Sources/Previews")
    .violations(matching: .calls("#Preview"))
  #expect(violations.isEmpty)
}
```

You can also restrict `@testable` imports to your test code:

```swift
@Test("Production code has no @testable imports")
func testableImportsAreContained() async throws {
  let violations = try await Codebase.app.imports
    .violations(matching: .hasAttribute("testable"))
  #expect(violations.isEmpty)
}
```

## Share rules across modules

You can put shared matchers and assertion helpers in a Swift package, then
import them from each module's test target:

```swift
extension Matcher where Subject == Class {
  public static let isWithinSizeLimit =
    Matcher("declare at most 20 functions") {
      $0.functions.count <= 20
    }
}

public func checkViewModel(_ viewModel: Class) {
  #expect(viewModel.inherits(from: "BaseViewModel"))
  #expect(viewModel.isFinal)
}
```

Each module defines its `Codebase` and `@Test` declarations, so it can choose
which shared checks to run and which baselines to apply. Test shared matchers
in their package with `.sources`.

If the modules live in one repository, you can instead check all their source
from one rules file or test target. Use a shared package when rules need to
be maintained across separate projects.

See <doc:GettingStarted> for setup and <doc:RunningRulesFromTheCLI> for shared
rules that can also run from the command line.
