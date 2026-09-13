# Inspect a rule's selections

Find which declarations a rule selects and excludes.

## Overview

If a rule passes when you expected a violation, check which declarations it
selected. A path or name filter might have removed the declaration before
the matcher ran.

List the project's rule IDs, then inspect one of them:

```sh
bylaws rules
bylaws rules --explain view-model-folders
```

Use the explanation to follow each query step's selected and excluded files or
declarations. The output includes their source locations and the rule's check
count, violations and warnings before applying any baseline.

For example, a `.suffixed("ViewModel")` step will list `OrderViewModel` under
`Selected` and `OrderView` under `Excluded`. Follow the steps in order to find
where an expected declaration disappeared.

If you run the command outside the project, use `--root` to select the project
directory. For a project with overrides, add `--for path` to inspect the rule
that applies there. This selects the rule rather than limiting the files it
can query.

Inspection exits with code 0 when the rule runs, even if it finds violations.
An unknown rule ID, a rules-file error or a failure to run the rule exits with
code 2. Use `bylaws lint` to enforce the result in CI.

## What gets recorded

The explanation shows Bylaws queries and filters such as `where`, `under`,
`outside` and `suffixed`. It starts after the source include and exclude
patterns apply, and omits standard library operations on arrays, sets and
other collections.

Put a query inside the rule body to inspect its filters. Queries evaluated
before the body runs are outside the explanation.

A package-dependency or folder-layout check may have results without a
selection query. In that case, the output shows the findings and reports that
no selections were recorded.

Build the project before inspecting a rule that needs compiler-index data.

## Inspect a rule in Swift

You can call `Rule.inspect()` in a test or your own tool to get the same
`findings` and `selections`. Each selection step contains a query description
with the selected and excluded elements.

For example, this rule checks the path of each view model:

```swift
import Bylaws

let app = Codebase(including: ["Sources/**"])
let rule = Rule("view-model-folders", "View models belong in ViewModels") {
  try await app.classes.suffixed("ViewModel")
    .violations(outsidePaths: "Sources/*/ViewModels/**")
}

let inspection = try await rule.inspect()
for step in inspection.selections {
  print(step.queryDescription)
  print("Selected:", step.selected.compactMap(\.name))
  print("Excluded:", step.excluded.compactMap(\.name))
}
```
