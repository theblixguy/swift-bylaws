# Check dependencies between files and folders

Choose permitted references and reject cycles between named groups of files.

## Overview

You can choose which files may reference other files, then check for cycles
between named groups of files. The rules use the references that Swift records
during a build, including references between files in one module.

All file patterns are relative to the codebase root. Replace the example
folders, such as `Presentation` and `Domain`, with your project's paths.

## Permit references in one direction

Suppose `Presentation` can use `Domain`, while `Domain` must remain independent
of `Presentation`. Save these rules in `Bylaws.swift`:

```swift
import Bylaws
import BylawsIndex
import Testing

let app = Codebase(including: ["Sources/**"])

let projectRules: [Rule] = [
  Rule(
    "presentation-dependencies",
    "Presentation references only its own code and Domain"
  ) {
    try await app.checkDependencies(
      from: ["Sources/Presentation/**"],
      allowingReferencesTo: ["Sources/Presentation/**", "Sources/Domain/**"],
      modules: ["App"]
    )
  },
  Rule("domain-dependencies", "Domain references only its own code") {
    try await app.checkDependencies(
      from: ["Sources/Domain/**"],
      allowingReferencesTo: ["Sources/Domain/**"],
      modules: ["App"]
    )
  },
]
```

Replace `App` with your build's module name and build it before running
`bylaws lint`.
You can also run the rules through Swift Testing with the `BylawsIndex`
product in the test target's dependencies.

Use `from:` to select the files to check and `allowingReferencesTo:` to select
the files they may reference. A reference to another selected project file
produces a violation if its path is outside that list. The source and
destination patterns may overlap.

References within one file are permitted. To permit references between files
in the same source group, include that group's path in
`allowingReferencesTo:`, as both rules do above.

You can use `Layering` and `indexedFindings(of:)` to declare permissions between
named groups, or `checkDependencies` to give the source and destination paths
directly.

## Apply a rule to each matching folder

Suppose each folder under `Sources/Components` can use its own files and
files under `Sources/Common`. Add this rule to the same array:

```swift
Rule("component-dependencies", "Components use their own files and Common") {
  try await app.checkDependencies(
    from: ["Sources/Components/**"],
    allowingReferencesTo: ["Sources/Common/**"],
    allowingWithinFoldersMatching: "Sources/Components/*",
    modules: ["App"]
  )
}
```

This rule also applies to components you add later. Files within each matching
folder may reference one another, including files in subfolders. References
to another component must match `allowingReferencesTo:`.

To permit references to selected files in other components, add a destination
pattern such as `"Sources/Components/*/Contracts/**"` with your own folder
names.
The referenced declarations must also be accessible under Swift's access rules.

To restrict what `Common` may reference, add a separate rule with
`from: ["Sources/Common/**"]` and its permitted destinations.

Choose a pattern that matches one folder level, such as `Sources/Components/*`.
Matching a parent and its child can put a file in two groups, which is a
configuration error. Use <doc:FolderRules> to check empty folders and resources
as well as folders with selected Swift files.

## Check dependency cycles separately

Groups let you check cycles between parts of your project even when their
files live in different folders. For example, Orders can include its feature
folder and an older checkout implementation:

```swift
Rule(
  "dependency-cycles",
  "Orders, Payments and Support have no dependency cycles"
) {
  try await app.checkDependencyCycles(
    between: [
      .init("Orders", files: [
        "Sources/Features/Orders/**",
        "Sources/Legacy/Checkout/**",
      ]),
      .init("Payments", files: [
        "Sources/Features/Payments/**",
        "Sources/Services/Billing/**",
      ]),
      .init("Support", files: ["Sources/Common/**", "Sources/Utilities/**"]),
    ],
    modules: ["App"]
  )
}
```

The check reports one cycle at a time, such as `Orders -> Payments -> Orders`,
with source locations for the dependencies involved. After fixing it, run the
rule again to check for remaining cycles.

Each `.init` creates a `DependencyGroup` with a distinct, non-empty name and
root-relative patterns that select its files. Several patterns in one
group may match the same file, but a file cannot belong to two groups.

You can save the groups in a `[DependencyGroup]` array, combine arrays with `+`
or create groups with `map`. These forms work in Swift Testing and the CLI.
The check includes references between groups and excludes references within
one group or outside all groups. `checkDependencies` permits cycles, so add a
cycle rule if you want to reject them.

### Create groups from folders

When each folder under `Sources/Features` is a group, use folder discovery:

```swift
Rule("feature-cycles", "Features have no dependency cycles") {
  let groups = try await app.dependencyGroups(
    inFoldersMatching: "Sources/Features/*"
  )
  try await app.checkDependencyCycles(between: groups, modules: ["App"])
}
```

Each matching folder becomes a group named after its path relative to the
codebase root, with selected Swift files from that folder and its subfolders.

Folders without selected Swift files are omitted, and the cycle check warns
when no groups remain. The groups must not overlap, and folder paths cannot
contain `*`, `?` or backslashes.

## Select the code and build to check

Both checks cover definitions in the selected `Codebase`, so excluding a folder
also excludes its definitions from the checks. To forbid a dependency, keep its
files selected and omit them from the permitted destination patterns.
Definitions outside the selection, including those in external libraries, are
not checked.

The compiler index covers the active `#if` branches in the selected build.
Rebuild after source changes and include all relevant modules when the files
belong to separate targets. If the index contains several build configurations,
select one with `unitOutputFiles:`.

Both checks ignore implicit compiler-generated references. They warn about
ambiguous definitions, empty selections and missing indexed declarations or
references. A missing module or unavailable index stops the rule with an error.

Editor checks and `bylaws lint --source-only` reject index queries. If your
editor runs source-only checks, save these rules in `DependencyRules.swift`
and run them separately:

```sh
bylaws lint --rules DependencyRules.swift
```
