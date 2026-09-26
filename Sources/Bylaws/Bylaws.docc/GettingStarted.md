# Getting started

Set up Bylaws to run with your tests or from the command line.

## Overview

You can run rules with your tests or from the command line. A test target
supports the full Swift language, while rules shared with the CLI must use its
supported subset as described in <doc:RunningRulesFromTheCLI>.

## Requirements

- Swift 6.2 or later, included with Xcode 26 or later
- Libraries: iOS 13 or later, macOS 14 or later or Linux
- Command-line tool: macOS 14 or later or x86-64 Linux

## Choose a workflow

| Workflow | Start here when | Main command |
| --- | --- | --- |
| Swift Testing | The rule belongs with the project's tests or needs the full Swift language | `swift test` |
| Portable rules | The rule must run before a build or through the editor integration | `bylaws lint` |

A portable rules file can also belong to a test target, so you can maintain
one file for both workflows.

## Add rules to a test target

Add the package and the `Bylaws` product to a test target:

```swift
dependencies: [
  .package(
    url: "https://github.com/theblixguy/swift-bylaws.git",
    from: "0.6.1"
  )
],
targets: [
  .testTarget(
    name: "AppTests",
    dependencies: [
      .product(name: "Bylaws", package: "swift-bylaws")
    ]
  )
]
```

The default `CLI` and `LanguageServer` package traits add the command-line and
editor tools. If you only use Bylaws in tests, omit the default traits:

```swift
.package(
  url: "https://github.com/theblixguy/swift-bylaws.git",
  from: "0.6.1",
  traits: []
)
```

Use `traits: ["CLI"]` to keep the command-line product without the
language-server dependency.

Next, define the files that the rules check:

```swift
import Bylaws

extension Codebase {
  nonisolated static let app = Codebase(
    root: .automatic(),
    including: ["Sources/**"]
  )
}
```

`root: .automatic()` searches upwards from the rule's source file for the
nearest Swift package, Xcode project, Git repository or Bazel workspace.
The include and exclude patterns are relative to that directory.

You can pass a query as a test's arguments to check each selected declaration.
This rule checks that functions which call `UserDefaults` belong to
`PreferencesStore`:

```swift
import Testing

@Suite(.codebase(.app))
struct PersistenceBoundaryRules {
  @Test(
    "Functions that call UserDefaults belong to PreferencesStore",
    .annotatesViolations,
    arguments: try await Codebase.app.functions.where(.calls("UserDefaults"))
  )
  func userDefaultsIsContained(_ function: Function) {
    #expect(function.enclosingTypeName == "PreferencesStore")
  }
}
```

You can see each function's result in the test output and use the failure's
file and line number to find the code to change. Swift Testing shows a skipped
test when no functions match the query.
<doc:DeclarationRules> includes checks for calls in property initialisers
and accessors.

## Configure caches for tests

You can choose disk-cache settings for a suite with `.parseCache`. For example,
this suite reads and hashes each source file before reusing its cached parse:

```swift
@Suite(.codebase(.app), .parseCache(validation: .content))
struct ArchitectureRules {
  @Test("Classes are final")
  func finalClasses() async throws {
    let classes = try await Codebase.app.classes
    #expect(classes.allSatisfy(\.isFinal))
  }
}
```

The trait also takes `directory` and `budget`, so you can set a cache directory
`URL` or change the soft disk-size target without repeating the validation
setting. Omitted arguments keep the enclosing suite's settings. At the outermost
scope, the defaults are the directory from `BYLAWS_CACHE_PATH` or the user's
caches directory, a 1 GB target and metadata validation. If you want to disable
the disk cache for one test, add `.parseCache(budget: 0)` to its `@Test` attribute.

A trait with a non-zero budget enables caching even for temporary projects
and overrides `BYLAWS_DISABLE_PARSE_CACHE`. An explicit `Codebase(parseCache:)`
configuration takes precedence over the trait. Bylaws resolves the settings
when you query the codebase, so stored and static codebases can use them too.
The order of `.codebase` and `.parseCache` in the suite attribute makes no
difference to preparation.

For discovered rules, `.selectionCache(budget: 32 * 1024 * 1024)` gives the
suite one shared budget for retained query selections. You can omit `budget`
to use 64 MiB or set it to zero to disable selection reuse. A nested suite or
test with its own trait gets a separate cache and budget, which Bylaws clears
when that scope finishes. Parsed files and running rules use additional memory.
Native Swift filter chains and custom closures keep their usual behaviour.

Both traits apply while tests run, including all parameterised cases. Swift
Testing evaluates `arguments:` before entering these scopes. If a query builds
the argument list, set `Codebase(parseCache:)` explicitly to configure its disk
cache, or move the query into the test body to use trait settings.

Parallel suites have independent settings, though suites that choose the same
disk directory share its entries and cleanup behaviour. See
<doc:RunningRulesFromTheCLI#Performance> for validation modes and cache limits.

## Set up an Xcode project

Choose **File > Add Package Dependencies**, enter the repository URL and add
the `Bylaws` product to the app's test target rather than the app target.

You can check the app and its local packages from one test target. Select
their source directories in the same codebase:

```swift
extension Codebase {
  nonisolated static let app = Codebase(
    root: .automatic(),
    including: ["MyApp/**", "Packages/**/Sources/**"],
    excluding: ["**/.build/**"]
  )
}
```

You can keep Bylaws in the app's test target without adding it to each local
package. Place the shared rules near the Xcode project so `.automatic()` finds
the project root rather than a local package's root.

You can also keep `Bylaws.swift` at the repository root and run the CLI as
described below. Package checks such as `checkPackageDependencies()` read one
`Package.swift`, so give each local package its own codebase while keeping the
rules in the central file.

## Set up a Tuist project

Add Bylaws to the dependencies in `Tuist/Package.swift` so Tuist manages it
alongside the project's other packages:

```swift
.package(
  url: "https://github.com/theblixguy/swift-bylaws.git",
  from: "0.6.1"
)
```

In the same file, enable testing search paths for the `Bylaws` target so
Xcode can find Swift Testing's macro plugin:

```swift
#if TUIST
  import struct ProjectDescription.PackageSettings

  let packageSettings = PackageSettings(
    targetSettings: [
      "Bylaws": .settings(base: ["ENABLE_TESTING_SEARCH_PATHS": "YES"])
    ]
  )
#endif
```

If the file has a `packageSettings` declaration, add the `Bylaws` entry to
its `targetSettings`. In `Project.swift`, add the product to your test
target's dependencies:

```swift
.external(name: "Bylaws")
```

Run `tuist install` and `tuist generate`, then open the workspace and run
the tests. Use this setup instead of adding Bylaws through Xcode's package
menu, which can create duplicate build targets for shared dependencies.

## Exclude generated files

A rule can report violations in generated code. If the fix belongs in the
generator, you can exclude its output from the checks:

```swift
let app = Codebase(
  root: .automatic(),
  including: ["Sources/**"],
  excluding: ["**/*.generated.swift", "**/*.pb.swift"]
)
```

An exclude pattern takes precedence when a file matches both lists. You can
use these patterns in tests and CLI rules.

## Run rules before a build

Install Bylaws with Homebrew on macOS or Linux:

```sh
brew install theblixguy/tap/bylaws
```

You can also download the CLI from the
[GitHub releases page](https://github.com/theblixguy/swift-bylaws/releases).

Create a rules file and check it from the project root:

```sh
bylaws init
bylaws lint
```

`bylaws init` creates advisory rules so you can see the current violations
without failing the run. You can edit that file to add your own rules.

For CLI-only rules, keep `Bylaws.swift` outside the app and test targets. In
Xcode, clear its **Target Membership**. In a Swift package, place it beside
`Package.swift`.

The command returns status 0 when the selected rules pass, 1 when an enforced
rule finds a violation and 2 when a rules file cannot load. You can select rules
with `--only` and `--skip` or add `--strict` to make advisory violations fail
the run too.

See <doc:RunningRulesFromTheCLI> for output formats, rule discovery and CI
setup.

## Introduce a rule gradually

An advisory rule reports issues without failing the run while you update the
codebase. Change its enforcement to `.enforced` when the rule has no
violations.

A baseline records the existing violations so you can reject new ones while
you fix the codebase.
<doc:RuleAdoption> explains both approaches and how to test a custom rule.

## Choose the next guide

You can find more examples in <doc:RuleCookbook>. If a check depends on inferred
types, generated code or a particular build configuration, read
<doc:WhatBylawsReads> before choosing its query.
