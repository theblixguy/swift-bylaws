# Running rules from the CLI

Run architectural rules from the command line or in CI.

## Overview

You can use the `bylaws` command to check rules from a `Bylaws.swift` file
without adding a test target. You can run these checks locally or in CI without
building your project first. Rules that use the compiler index need data from
a build.

## Install the CLI

Install Bylaws with Homebrew on macOS or Linux:

```sh
brew install theblixguy/tap/bylaws
```

You can also download the CLI from the
[GitHub releases page](https://github.com/theblixguy/swift-bylaws/releases).

For automatic checks during a SwiftPM build, see <doc:RunningRulesDuringBuilds>.

## The rules file

You can write rules with the CLI's <doc:RunningRulesFromTheCLI#Supported-API>
and run them from a test target too. The guides call these rules "portable".

Save this example as `Bylaws.swift` at the project root:

```swift
import Bylaws
import Testing

nonisolated let app = Codebase(
  root: .automatic(),
  including: ["Sources/**"]
)

nonisolated func hasAtMostTwentyFunctions(
  _ declaration: Class
) -> Bool {
  declaration.functions.count <= 20
}

nonisolated let isWithinSizeLimit =
  Matcher<Class>("declare at most 20 functions") {
    hasAtMostTwentyFunctions($0)
  }

nonisolated let projectRules: [Rule] = [
  Rule("class-size", "Classes stay within the size limit") {
    try await app.classes.violations(of: isWithinSizeLimit)
  },
]
```

## Run the rules

Run the rules from the project root:

```sh
bylaws lint
```

If you want to start with warning-only rules instead of the example above,
run `bylaws init` in a project that has no `Bylaws.swift` file. It creates
advisory rules, which report violations without failing the run. The generated
codebase excludes DocC bundles with `**/*.docc/**`. If you want to check their
Swift examples too, remove that pattern from the `excluding` list.

The run exits with status code 0 when the rules pass, status code 1 when it
finds an enforced violation and status code 2 when it cannot load a rules file.
Xcode displays violations from the default `xcode` output format alongside
compiler messages. A warning about an empty rule or layer means you should
check which files the rule selects.

For CI, choose the `github` format for pull request annotations, `sarif` for
code scanning or `json` for another tool.

You can save a report with `--output` and see violations and warnings in the
terminal when the checks finish:

```sh
bylaws lint --format json --output report.json
```

The report replaces the file's contents, and diagnostics go to standard error.
If the file cannot be written, the command exits with status code 2. Use
`--record-baseline` in a separate run.

To check a project from another directory, use `--root`. Relative `--rules`,
`--baseline`, `--report-path` and `--changed-path` values refer to that project
root. Paths for `--output`, `--record-baseline` and `--cache-path` refer to your
working directory, so you can keep generated files outside the project:

```sh
bylaws lint --root Projects/App --rules Bylaws.swift --output report.txt
```

Within a rules file, a relative `Codebase(root: .directory(...))` path starts
from the directory that contains that file.

You can select rules by ID with `--only` and `--skip`. Advisory violations
appear as warnings without failing the run unless you add `--strict`.

Use `--report-path` to report violations and source-located warnings for
particular files or directories. Pass several paths after one option or
repeat the option:

```sh
bylaws lint --report-path Sources/Domain Tests/DomainTests.swift
```

You can use `--report-path` in a staged-file hook to report violations from
changed files while checking their dependencies against the whole codebase.
Each path includes its descendants and can be absolute or relative to the
project root. Violations and source-located warnings outside those paths are
omitted, but configuration errors and stale baseline entries apply to the
whole run.

When another tool gives you a complete list of files changed since the previous
run, pass them to `--changed-path`. Bylaws then enables the disk cache, rechecks
the rules affected by those paths and uses cached results for the rest:

```sh
bylaws lint --changed-path Sources/Checkout/CheckoutView.swift
```

Include changed generated inputs too, such as a refreshed Bazel graph, because
a version-control diff might not list them.

Each affected rule checks all of its inputs again, which means a change in one
file can reveal a violation in another. Bylaws runs every rule when no result
cache exists and always reruns a rule when it cannot track all of its inputs.
Rules that use compiler-index data also run every time because the index can
change independently of source files.

## Discovery and overrides

The CLI reads SwiftPM language settings automatically. For an Xcode project,
set `swiftLanguageMode: .v5` or `.v6` in the `Codebase` declaration, or use
`.automatic(.xcode)` to read its settings. Use
`.automatic([.swiftPM, .xcode])` to include local package settings too. See
<doc:WhatBylawsReads#Swift-language-mode> for the discovery limits.

You can keep project-wide rules in the root `Bylaws.swift` and add a
`Bylaws.swift` in any folder that needs its own rules. Each file uses its folder
as the default codebase root, including in Xcode and Bazel projects.

Rules from parent folders also apply unless you replace one with an `Override`
that explains the exception. For example, `Modules/Billing/Bylaws.swift` can
contain:

```swift
let billing = Codebase(including: ["Sources/**"])

Override("layers", reason: "billing migrates to the new layering in Q4") {
  billing.files.violations(matching: .imports("LegacyUI"))
}
```

The parent rule continues to run outside `Modules/Billing`. If a subfolder has
another override for the same rule, that override applies within the subfolder.
You can see which rules apply to a path and why they were overridden with
`bylaws rules --for Modules/Billing/Sources`:

```text
layers
  Modules import their own layer
  override: billing migrates to the new layering in Q4
  Modules/Billing/Bylaws.swift:3
```

Write an exemption as a `Codebase` exclusion in the root file so code owners can
review it with the rule. Use a baseline to record existing violations while
continuing to report each new one.

### Exclude folders from discovery

You can exclude rules and baselines in generated or vendor folders by adding
`RuleDiscovery` to the root `Bylaws.swift`:

```swift
RuleDiscovery(excluding: ["Vendor", "**/Generated"])
```

This skips the root `Vendor` folder and any folder named `Generated`, including
their contents. Bylaws also skips `.git`, `.build`, `.swiftpm`, `DerivedData`,
`node_modules` and `Pods` automatically.

These settings apply to rule and baseline discovery in the CLI, tests and
editors. To exclude source files from a rule's checks, use the `excluding`
argument on its `Codebase` instead. You can load a rule or baseline file from an
excluded folder by passing its path to `--rules` or `--baseline`.

## Share rules through SwiftPM

To share rules between projects, put them in a Swift library target with a
public function that takes a `Codebase` and returns the rules to run:

```swift
public import Bylaws
import Testing

public nonisolated func companyRules(for codebase: Codebase) -> [Rule] {
  let finalClass = Matcher<Class>("be final") { $0.isFinal }

  return [
    Rule("company-final-classes", "Classes are final") {
      try await codebase.classes.violations(of: finalClass)
    },
  ]
}
```

SwiftPM makes command plugins available from direct dependencies, so list
Bylaws and the rule package as direct dependencies of the consuming package.
Add both library products to the test target that compiles the rules.

Import the rule module from `Bylaws.swift` and pass it the local codebase:

```swift
import Bylaws
import CompanyRules

nonisolated let app = Codebase(
  root: .automatic(),
  including: ["Sources/**"]
)

nonisolated let rules = companyRules(for: app)
```

Run the package command without installing `bylaws` separately. The
`--allow-writing-to-package-directory` flag lets it save a baseline when you
request one:

```sh
swift package --allow-writing-to-package-directory bylaws
```

Rules that import a shared package need the SwiftPM command. The standalone
`bylaws lint` command supports self-contained rules files only.

If your rules file is outside a discovery location, pass its path through the
plugin:

```sh
swift package --allow-writing-to-package-directory bylaws \
  --rules Config/Architecture.swift
```

In both workflows, `.automatic()` searches upwards from the rules file for the
nearest project root. A file under a local package starts at that package,
even when the command runs from the repository root.

## In CI

An enforced violation exits with status code 1, so a `bylaws lint` step fails a
build on its own. Use the `github` format for pull request annotations or
`sarif` for code scanning.

When the rules import a Swift package, use the plugin in CI:

```yaml
- name: Check the rules
  run: >-
    swift package --allow-writing-to-package-directory bylaws
    --format github
```

The CLI runs rules without compiling them, so include the rule target in a CI
build or test job to check for compiler errors too.

### Annotations on a pull request

Use `--format github` to show violations as annotations on the workflow run and
pull request:

```yaml
jobs:
  bylaws:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install the CLI
        run: |
          BASE=https://github.com/theblixguy/swift-bylaws/releases
          curl -fsSL -o bylaws.tar.gz \
            "$BASE/latest/download/bylaws-linux.tar.gz"
          tar -xzf bylaws.tar.gz ./bin/bylaws
      - name: Check the rules
        run: ./bin/bylaws lint --format github
```

GitHub displays at most 10 errors, 10 warnings and 10 notices from one step,
even when Bylaws reports more. Use `--only` to limit the run to the rules you
want to annotate.

### Code scanning

To add violations to GitHub code scanning, write a [SARIF][sarif] report with
`--format sarif` and upload it with `upload-sarif`. The job needs
`security-events: write` permission:

```yaml
jobs:
  bylaws:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write
    steps:
      - uses: actions/checkout@v4
      - name: Install the CLI
        run: |
          BASE=https://github.com/theblixguy/swift-bylaws/releases
          curl -fsSL -o bylaws.tar.gz \
            "$BASE/latest/download/bylaws-linux.tar.gz"
          tar -xzf bylaws.tar.gz ./bin/bylaws
      - name: Write the report
        run: ./bin/bylaws lint --format sarif > bylaws.sarif || true
      - uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: bylaws.sarif
```

This example uses `|| true` to upload the report even when Bylaws finds a
violation. It leaves the job passing, so add a separate `bylaws lint` step if
violations should fail CI.

Code scanning is available for public repositories on GitHub.com. For a private
repository, check GitHub's [code scanning requirements]
before adding the upload step.

The report includes each rule's ID, name and hint, with `error` for enforced
violations and `warning` for advisory violations. Each result uses a related
location for the rule declaration, with file paths relative to the project root.

[sarif]: https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html
[code scanning requirements]: https://docs.github.com/en/code-security/concepts/code-scanning/code-scanning

### JSON

You can use `--format json` to read results in a script or another tool. The
report uses `schemaVersion: 1`, with a `rules` array for the checked rules,
an `events` array for violations, warnings and diagnostics and a `summary`
with rule and violation counts. Each rule includes the path, line and column of
its declaration. Event paths are relative to the project root when possible,
and each event has a `kind` of
`violation`, `warning` or `diagnostic`, plus its level, message, location,
optional hint and optional rule ID.

## Baselines

To record the current violations, run:

```sh
bylaws lint --record-baseline Bylaws.baseline.swift
```

The CLI finds `Bylaws.baseline.swift` at the project root and beside each local
package's `Package.swift`. A package baseline applies within that package's
directory, while the root baseline applies throughout the project. These
baselines also work in tests. To use a different file in the CLI, pass
`--baseline` to replace the discovered baselines.

If a violation recorded in the baseline is no longer present, the command
reports its entry and exits with status code 1. Review the fix before recording
the baseline again to remove that entry. This check applies to rules that ran,
so `--only` and `--skip` leave entries for other rules unchecked. Recording a
baseline must cover the full run and cannot use rule selection or
`--report-path`.

## Run a rules file as tests

To run your rules as tests, add the rules file to a test target and call
`report()` for each `Rule`. A direct call to a check such as
`checkPackageDependencies()` returns findings without recording test issues,
so keep the check in a `Rule` body and let `report()` report the results.

Put the test declaration in a separate file so the rules file can also run
through the CLI:

```swift
import Bylaws
import Testing

@Test("Code follows the architecture rules", arguments: projectRules)
func architecture(_ rule: Rule) async throws {
  try await rule.report()
}
```

If you want to keep `Bylaws.swift` outside the test target, add the
`BylawsInterpreter` product and use `Rule.discovered()`. You can then edit the
rules without recompiling the test target:

```swift
import Bylaws
import BylawsInterpreter
import Testing

@Suite("Bylaws")
struct DiscoveredRules {
  @Test(
    "Code follows the architecture rules",
    arguments: try await Rule.discovered()
  )
  func architecture(_ rule: Rule) async throws {
    try await rule.report()
  }
}
```

You can see each discovered rule's result under its name in the test output,
with the declaration's location for violations and the call site for warnings.
`report()` uses the rule's enforcement setting, but you can pass
`enforcement: .enforced` to make advisory violations fail the test too.

Discovery supports the same Swift subset as the CLI. To use the full Swift
language, write the rule as an ordinary test.

## Performance

Use `--cache` to reuse parsed files between runs and save the rule results that
`--changed-path` needs. Caching is off by default and can be slower than running
without it, so compare the timings on your project.

If the cache must live in a particular directory, pass `--cache-path DIR`.
You can copy this directory between CI workers or reuse it after moving a
checkout. Entries match the source text and Swift language mode, and violations
use the current checkout's file paths.

If a parsed entry is missing or damaged, Bylaws parses that source file again.
If saved rule results are damaged, Bylaws runs those rules again.

You can adjust the default disk-cache target of 1,000,000,000 bytes with
`--cache-size 500MB`, which also enables caching. The option takes whole bytes
or a case-insensitive `B`, `KB`, `MB`, `GB`, `KiB`, `MiB` or `GiB` suffix,
with decimal units using powers of 1,000 and binary units using powers of
1,024. If you want to disable the disk cache while keeping its existing
entries, pass `--cache-size 0`.

Bylaws normally cleans up the cache at most once a day and removes the oldest
entries first. The cache can grow beyond the requested size between cleanups,
so the size setting is a soft target. If you change it, Bylaws runs cleanup the
next time it loads the cache, even if the previous cleanup was earlier that
day. The size is based on file lengths, which can differ from allocated disk
space, and applies only to the disk cache.

When caching is enabled, Bylaws uses metadata validation to check a file's
identity, size and precise modification and change times before and after
loading its cached model. It reads and hashes the source if the metadata has
changed, an entry is missing or damaged, or a timestamp is recent or ambiguous.
This can miss a source change if every checked metadata field is preserved.

If you want to read and hash each source file before accepting a hit, use
`--cache-validation content`, which also enables caching. You can switch
between validation modes while reusing the same parsed entries. Cached models
include their source text, which lets metadata validation skip the source
read when the file's metadata is unchanged.

In Swift tests, you can set defaults for a suite or test with
`.parseCache(validation: .content)`. The trait also takes `directory` and `budget`,
and inherits omitted settings from its enclosing scope. See
<doc:GettingStarted#Configure-caches-for-tests> for examples and precedence.
You can give an individual codebase an explicit configuration, which takes
precedence over those defaults:

```swift
let codebase = Codebase(
  root: .directory(projectPath),
  parseCache: .init(
    directory: cacheDirectory,
    budget: 500_000_000,
    validation: .content
  )
)
```

In this example, `cacheDirectory` is a `URL` to the directory where Bylaws
creates its `Bylaws` cache folder. You can give each test its own directory
to keep parallel tests independent. If several tests share a directory,
a test configured with a smaller budget may delete files cached by another
test during cleanup. Bylaws will parse those source files again if they're
needed.

When you set `parseCache` with a budget greater than zero, Bylaws caches files
even in temporary directories and ignores `BYLAWS_DISABLE_PARSE_CACHE` for
that codebase. You can set `directory` to override `BYLAWS_CACHE_PATH` or leave
it out to use that environment value or the user's caches directory. If you
leave out `parseCache`, Bylaws uses the environment settings for the codebase.

If you want to configure all tests through the environment, set
`BYLAWS_CACHE_PATH` to choose their cache directory or
`BYLAWS_DISABLE_PARSE_CACHE=true` to disable caching. You can disable the cache
for an individual codebase by setting its `parseCache` budget to zero.

The CLI reuses selections from repeated name filters within each run, with
a default memory budget of 64 MiB. You can change the budget with
`--selection-cache-size`:

```sh
bylaws lint --selection-cache-size 32MiB
```

The option takes a value in whole bytes or with a case-insensitive suffix
of B, KB, MB, GB, KiB, MiB or GiB. KB, MB and GB use powers of 1000, while
KiB, MiB and GiB use powers of 1024. If you want to turn off selection reuse,
pass `--selection-cache-size 0`.

The budget covers the estimated memory used to cache selections across all
codebases in the run, including the original and filtered arrays, query keys
and cache entries. Bylaws also needs memory for parsed files and rules that
are running, so this setting does not limit the process's total memory use.
When there is no room for a new result, Bylaws removes the least recently used
cached results first. Rules can use results that are too large to cache, but
Bylaws may need to calculate them again for another rule.

For discovered rules in Swift Testing, add `.selectionCache(budget: 32 * 1024 * 1024)`
to a suite to share one cache across its tests. You can also share a cache across
selected calls to `report()` with `SelectionCache.withBudget`:

```swift
try await SelectionCache.withBudget(32 * 1024 * 1024) {
  for rule in rules {
    try await rule.report()
  }
}
```

Bylaws clears the cache after the closure finishes. You can reuse results
from `named`, `prefixed`, `suffixed` and `excluding` filters in compiled
portable queries. Native Swift filter chains and custom closures run as
usual, and inspection continues to show each filter step.

## Supported API

The portable language includes top-level and local `let` bindings, named
functions with explicit parameter and result types, closures, `return`, `if`,
`for` and single-condition `guard let`. It supports optional chaining and `??`,
string interpolation, key paths, comparisons, Boolean operators and array
concatenation. Collection calls include `filter`, `map`, `compactMap`,
`flatMap`, `contains`, `allSatisfy` and `isSubset(of:)`. Matcher and collection
predicates are synchronous and nonthrowing.

For rules that compare folders, you can use `URL(fileURLWithPath:)` with
`deletingLastPathComponent()`, `path`, `lastPathComponent` and `pathExtension`.
`Dictionary(grouping:by:)` groups declarations or other sequence values by a
`String`, `Int`, `Bool` or `URL` key. You can read a group with
`dictionary[key]` and use `mapValues` to transform each group, as shown in
<doc:CorrespondingTypes>.

You can use Bylaws queries, matchers, layering and package checks, including
`importGraph()` and the Bazel graph queries in <doc:BazelDependencies>.
The index and source-node queries in <doc:AdvancedRules> are also supported,
along with the SwiftSyntax APIs listed in the table below.

For example, a portable rule can inspect dependency requirements without
executing `Package.swift`:

```swift
let manifest = try await app.packageManifest
let allDependenciesArePinned = manifest.dependencies.knownValues.allSatisfy {
  $0.requirement.isExactVersion
}
```

This example checks the dependencies that Bylaws could read unconditionally,
so `knownValues` may contain only part of the list. When the check must cover
every dependency, use `values` and treat `nil` as an incomplete result.
`ManifestList` also provides separate lists for conditional and unresolved
values.

For manifest enum values, use `kind` or `valueKind` and the named properties
for associated data. Pattern matching is outside the CLI's supported subset.

The CLI supports the members listed below. Use a compiled test target for
other APIs.

<!-- runtime-capabilities:start -->
| Receiver | Properties | Methods |
| --- | --- | --- |
| `Actor` | `allInheritedTypes`, `attributes`, `documentation`, `enclosingTypeName`, `extensionInheritedTypes`, `functions`, `genericParameters`, `inheritedTypes`, `initializers`, `isDocumented`, `isNonisolated`, `location`, `name`, `properties`, `qualifiedName`, `sourceRange`, `sourceText`, `visibility` | `attribute`, `conforms`, `directlyConforms`, `directlyInherits`, `hasAttribute`, `inherits` |
| `Array` | `count`, `first`, `isEmpty` | `allSatisfy`, `compactMap`, `contains`, `filter`, `flatMap`, `map` |
| `Attribute` | `arguments`, `name` | None |
| `BazelGraph` | `targets` | `directTargetDependencies`, `transitiveTargetDependencies` |
| `BazelGraph.Configuration` | `buildOptions`, `checksum`, `isTool` | None |
| `BazelGraph.Target` | `configuration`, `description`, `label`, `location`, `ruleClass`, `tags` | None |
| `Class` | `allInheritedTypes`, `attributes`, `documentation`, `enclosingTypeName`, `extensionInheritedTypes`, `functions`, `genericParameters`, `inheritedTypes`, `initializers`, `isDocumented`, `isFinal`, `isNonisolated`, `location`, `name`, `properties`, `qualifiedName`, `sourceRange`, `sourceText`, `visibility` | `attribute`, `conforms`, `directlyConforms`, `directlyInherits`, `hasAttribute`, `inherits` |
| `ClassDeclSyntax` | `memberBlock` | None |
| `Codebase` | `actors`, `assignments`, `calls`, `classes`, `compilationBranches`, `enums`, `expressions`, `extensions`, `files`, `functions`, `imports`, `initializers`, `packageManifest`, `properties`, `protocols`, `structs`, `typealiases`, `types`, `variableBindings` | `bazelGraph`, `checkDependencies`, `checkDependencyCycles`, `checkDependencyStability`, `checkFolderLayout`, `checkLayering`, `checkPackageDependencies`, `conformers`, `definitions`, `dependencyGroups`, `directConformers`, `importGraph`, `indexedFindings`, `occurrences`, `projectIndex`, `references`, `syntaxNodes` |
| `CompilationBranch` | `condition`, `location`, `name`, `precedingConditions` | `contains` |
| `DeclarationLocation` | `column`, `fileName`, `filePath`, `line`, `utf8Offset` | None |
| `DependencyGroup` | `files`, `name` | None |
| `DependencyStabilityCheck` | `checkedEdgeCount`, `emptyTargets`, `isComplete`, `unresolvedManifestValues`, `unstable`, `violations` | `findings` |
| `DependencyStabilityCheck.UnstableDependency` | `importDeclaration`, `importedInstability`, `importedTarget`, `instability`, `target` | None |
| `Dictionary` | `count`, `isEmpty` | `mapValues` |
| `EnclosingDeclaration` | `location`, `name` | None |
| `Enum` | `allInheritedTypes`, `attributes`, `cases`, `documentation`, `enclosingTypeName`, `extensionInheritedTypes`, `functions`, `genericParameters`, `inheritedTypes`, `initializers`, `isDocumented`, `isIndirect`, `isNonisolated`, `location`, `name`, `properties`, `qualifiedName`, `sourceRange`, `sourceText`, `visibility` | `attribute`, `conforms`, `directlyConforms`, `directlyInherits`, `hasAttribute`, `inherits` |
| `EnumCase` | `documentation`, `enclosingTypeName`, `isDocumented`, `isIndirect`, `location`, `name`, `rawValue` | None |
| `Extension` | `allInheritedTypes`, `attributes`, `extendedTypeName`, `inheritedTypes`, `location`, `name`, `simpleExtendedTypeName`, `visibility` | `attribute`, `conforms`, `directlyConforms`, `directlyInherits`, `hasAttribute`, `inherits` |
| `FolderLayoutCheck` | `matchedFolders`, `missingFolders`, `unexpectedFolders` | `findings` |
| `Function` | `attributes`, `awaitCount`, `bodyLineCount`, `calls`, `cyclomaticComplexity`, `documentation`, `enclosingTypeName`, `genericParameters`, `isAsync`, `isDocumented`, `isDynamic`, `isMutating`, `isNonisolated`, `isOverride`, `isStatic`, `isThrowing`, `location`, `name`, `parameters`, `returnType`, `returnTypeName`, `sourceRange`, `sourceText`, `visibility` | `attribute`, `calls`, `hasAttribute` |
| `FunctionCall` | `argumentLabels`, `arguments`, `baseName`, `calledExpression`, `location`, `memberName`, `name` | `hasArgumentLabel`, `references` |
| `FunctionCall.Argument` | `expression`, `label`, `location`, `text` | None |
| `GenericParameter` | `constraintName`, `name` | None |
| `Import` | `attributes`, `kind`, `location`, `moduleName`, `name`, `visibility` | `attribute`, `hasAttribute` |
| `ImportGraph` | `targets` | None |
| `ImportGraph.Target` | `importedBy`, `imports`, `instability`, `name` | None |
| `IndexReference` | `column`, `file`, `line`, `location`, `module`, `roles`, `symbol` | None |
| `IndexSymbol` | `kind`, `name`, `usr` | None |
| `Initializer` | `attributes`, `awaitCount`, `calls`, `cyclomaticComplexity`, `documentation`, `isAsync`, `isConvenience`, `isDocumented`, `isFailable`, `isNonisolated`, `isThrowing`, `location`, `name`, `parameters`, `visibility` | `attribute`, `hasAttribute` |
| `LayeringCheck` | `emptyLayers`, `missingImports`, `violations` | `findings` |
| `LayeringCheck.MissingImport` | `layer`, `requiredImport` | None |
| `ManifestList` | `conditionalValues`, `isComplete`, `knownValues`, `possibleValues`, `unresolvedValues`, `values` | None |
| `Matcher` | `requirementDescription` | None |
| `MemberBlockSyntax` | `members` | None |
| `NominalType` | `allInheritedTypes`, `attributes`, `documentation`, `enclosingTypeName`, `extensionInheritedTypes`, `functions`, `genericParameters`, `inheritedTypes`, `initializers`, `isActor`, `isClass`, `isDocumented`, `isEnum`, `isNonisolated`, `isStruct`, `keyword`, `location`, `name`, `properties`, `qualifiedName`, `sourceRange`, `sourceText`, `visibility` | `attribute`, `conforms`, `directlyConforms`, `directlyInherits`, `hasAttribute`, `inherits` |
| `Offender` | `affectedPath`, `description`, `line`, `location`, `name`, `path`, `requirement` | None |
| `PackageDependencyCheck` | `checkedImportCount`, `emptyTargets`, `isComplete`, `undeclared`, `unresolvedManifestValues`, `unused`, `violations` | `findings` |
| `PackageDependencyCheck.UndeclaredDependency` | `importDeclaration`, `module`, `target` | None |
| `PackageDependencyCheck.UnusedDependency` | `module`, `target` | None |
| `PackageManifest` | `cLanguageStandard`, `cxxLanguageStandard`, `defaultLocalization`, `defaultTraitNames`, `dependencies`, `isComplete`, `name`, `platforms`, `products`, `swiftLanguageModes`, `targets`, `toolsVersion`, `traits`, `unresolvedValues` | `dependencies`, `directTargetDependencies`, `products`, `targets`, `testTargets`, `transitiveTargetDependencies` |
| `PackageManifest.Condition` | `configuration`, `platforms`, `traitNames` | None |
| `PackageManifest.Dependency` | `name`, `requirement`, `sourceKind`, `sourceLocation`, `traits` | None |
| `PackageManifest.Dependency.Requirement` | `branch`, `isExactVersion`, `kind`, `lowerBound`, `majorVersion`, `minimumVersion`, `revision`, `upperBound` | None |
| `PackageManifest.Dependency.TraitSelection` | `condition`, `kind`, `name` | None |
| `PackageManifest.Platform` | `minimumVersion`, `name` | None |
| `PackageManifest.PlatformVersion` | `components`, `description` | None |
| `PackageManifest.Product` | `isComplete`, `kind`, `linkage`, `name`, `targetNames` | None |
| `PackageManifest.Target` | `binarySource`, `buildSettings`, `dependencies`, `dependencyNames`, `excludedPaths`, `isComplete`, `isPlugin`, `isTest`, `kind`, `moduleName`, `name`, `packageAccess`, `path`, `pkgConfig`, `pluginCapability`, `plugins`, `providers`, `publicHeadersPath`, `resources`, `sourceDirectory`, `sources`, `unresolvedValues` | None |
| `PackageManifest.Target.BinarySource` | `checksum`, `kind`, `path`, `sourceLocation` | None |
| `PackageManifest.Target.Dependency` | `condition`, `isComplete`, `kind`, `name`, `packageName`, `unresolvedValues` | None |
| `PackageManifest.Target.NetworkPorts` | `kind`, `lowerBound`, `upperBound`, `values` | None |
| `PackageManifest.Target.NetworkScope` | `kind`, `ports` | None |
| `PackageManifest.Target.PluginCapability` | `intent`, `kind`, `permissions` | None |
| `PackageManifest.Target.PluginIntent` | `description`, `kind`, `verb` | None |
| `PackageManifest.Target.PluginPermission` | `kind`, `networkScope`, `reason` | None |
| `PackageManifest.Target.PluginUsage` | `name`, `packageName` | None |
| `PackageManifest.Target.Resource` | `localization`, `path`, `rule` | None |
| `PackageManifest.Target.Setting` | `arguments`, `condition`, `defaultIsolation`, `name`, `tool`, `usesUnsafeFlags`, `value`, `valueKind`, `warningLevel` | None |
| `PackageManifest.Target.SourceSelection` | `isComplete`, `kind`, `paths` | None |
| `PackageManifest.Target.SystemPackageProvider` | `kind`, `packages` | None |
| `PackageManifest.ToolsVersion` | `components`, `description` | None |
| `PackageManifest.Trait` | `description`, `enabledTraitNames`, `name` | None |
| `PackageManifest.UnresolvedValue` | `column`, `expression`, `field`, `line` | None |
| `PackageManifest.Version` | `buildMetadataIdentifiers`, `description`, `major`, `minor`, `patch`, `prereleaseIdentifiers` | None |
| `Parameter` | `label`, `name`, `type`, `typeName` | None |
| `ProjectIndex` | None | `conformers`, `definitions`, `directConformers`, `occurrences`, `references` |
| `Property` | `attributes`, `calls`, `documentation`, `isConstant`, `isDocumented`, `isDynamic`, `isLazy`, `isNonisolated`, `isNonisolatedUnsafe`, `isStatic`, `isWeak`, `location`, `name`, `ownership`, `type`, `typeName`, `visibility` | `attribute`, `calls`, `hasAttribute` |
| `ProtocolDeclaration` | `allInheritedTypes`, `attributes`, `documentation`, `extensionInheritedTypes`, `inheritedTypes`, `isDocumented`, `isNonisolated`, `location`, `name`, `requiredFunctions`, `requiredProperties`, `sourceRange`, `sourceText`, `visibility` | `attribute`, `conforms`, `directlyConforms`, `directlyInherits`, `hasAttribute`, `inherits` |
| `Range<Int>` | `count`, `isEmpty`, `lowerBound`, `upperBound` | `contains` |
| `Rule.Findings` | `checks`, `violations`, `warnings` | `findings` |
| `Rule.Warning` | `location`, `message` | None |
| `RuleResults` | None | `findings` |
| `Selection` | `count`, `first`, `isEmpty`, `queryDescription` | `allSatisfy`, `compactMap`, `contains`, `excluding`, `filter`, `flatMap`, `map`, `nameMatching`, `named`, `outside`, `prefixed`, `suffixed`, `under`, `violations`, `where` |
| `Set` | `count`, `isEmpty` | `allSatisfy`, `compactMap`, `contains`, `filter`, `flatMap`, `isSubset`, `map` |
| `Set<SymbolRole>` | None | `contains` |
| `SourceAssignment` | `compilationBranches`, `enclosingDeclarations`, `location`, `name`, `operatorName`, `target`, `value` | None |
| `SourceExpression` | `arguments`, `arrayElements`, `base`, `booleanValue`, `calledExpression`, `compilationBranches`, `dictionaryElements`, `enclosingDeclarations`, `floatingPointValue`, `integerValue`, `interpolations`, `isNilLiteral`, `location`, `name`, `referenceLocation`, `referenceName`, `stringValue`, `text` | None |
| `SourceExpression.Argument` | `expression`, `label` | None |
| `SourceExpression.DictionaryElement` | `key`, `value` | None |
| `SourceFile` | `actors`, `assignments`, `calls`, `classes`, `compilationBranches`, `enums`, `expressions`, `extensions`, `functions`, `imports`, `initializers`, `lineCount`, `location`, `name`, `path`, `properties`, `protocols`, `sourceText`, `structs`, `typealiases`, `types`, `variableBindings` | `calls`, `imports`, `withSyntax` |
| `SourceFileSyntax` | None | `tokens` |
| `SourceNode` | `ancestors`, `call`, `children`, `descendants`, `description`, `expression`, `kind`, `location`, `parent`, `text` | None |
| `String` | `count`, `description`, `first`, `isEmpty` | `contains`, `hasPrefix`, `hasSuffix`, `lowercased` |
| `Struct` | `allInheritedTypes`, `attributes`, `documentation`, `enclosingTypeName`, `extensionInheritedTypes`, `functions`, `genericParameters`, `inheritedTypes`, `initializers`, `isDocumented`, `isNonisolated`, `location`, `name`, `properties`, `qualifiedName`, `sourceRange`, `sourceText`, `visibility` | `attribute`, `conforms`, `directlyConforms`, `directlyInherits`, `hasAttribute`, `inherits` |
| `TokenSyntax` | `leadingTrivia`, `text`, `trailingTrivia` | None |
| `TriviaPiece` | `description`, `isComment` | None |
| `TypeReference` | `elementType`, `genericArguments`, `isArray`, `isDictionary`, `isExistential`, `isFunction`, `isOpaque`, `isOptional`, `isSet`, `isTuple`, `keyType`, `name`, `text`, `valueType` | `references` |
| `Typealias` | `aliasedTypeName`, `attributes`, `documentation`, `isDocumented`, `location`, `name`, `visibility` | `attribute`, `hasAttribute` |
| `URL` | `lastPathComponent`, `path`, `pathExtension` | `deletingLastPathComponent` |
| `VariableBinding` | `compilationBranches`, `enclosingDeclarations`, `initialValue`, `isMutable`, `location`, `name` | None |
| `Violations` | `checkedCount`, `count`, `isEmpty`, `offenders`, `rule` | `findings` |
<!-- runtime-capabilities:end -->

Portable files may import `Bylaws`, `Testing`, `Foundation`, `BylawsIndex`,
`BylawsIndexStore` and `BylawsSyntax`, while existing rules can continue to
import `SwiftSyntax`. Use `BylawsSyntax` for new rules that work with syntax
types. The SwiftPM command can also import portable source targets from the
resolved package graph.

Add the package products for the modules you import, such as `Bylaws`,
`BylawsIndex` and `BylawsIndexStore`. `BylawsSyntax` is part of the `Bylaws`
product, while `Testing` comes from the Swift toolchain. A rule that imports
`SwiftSyntax` directly also needs the `SwiftSyntax` product.

Shared rule modules support public functions and bindings with internal
helpers. Reserve the top-level name `rules` for a `[Rule]` array. The module's
source must use the same Swift subset as the rules file, with
`internal`, `public` and `nonisolated` declaration modifiers. File-scoped and
`package` access are unsupported.

In a `[Rule]` binding, rule bodies can combine check expressions with `if` and
`for`. `Array { ... }` builds a rule list, and `Layering { ... }` builds a layer
list. A loop binds each element of an array, set or selection to one name.
Standalone `Rule` and `Override` declarations take one query per rule body.

Custom result builders, mutable state, switches, nominal type and generic
declarations, overloads, macros and unrestricted system APIs are outside the
subset. The CLI reports the file and line of unsupported code.
