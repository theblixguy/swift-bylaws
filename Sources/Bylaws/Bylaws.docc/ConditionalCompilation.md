# Conditional compilation

Check where code appears in a conditional-compilation branch.

## Keep a setting inside a debug branch

You can check the `#if` context of an expression, assignment or variable
binding. For example, this rule checks that assignments of `true` to
`allowsInsecureConnections` are inside a branch whose condition is `DEBUG`:

```swift
import Bylaws

let codebase = Codebase(including: ["Sources/**"])

let rules: [Rule] = [
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
  },
]
```

The assignment below passes this rule:

```swift
#if DEBUG
settings.allowsInsecureConnections = true
#endif
```

The same assignment fails in the `#else` branch or outside the conditional
block. The matcher checks for the exact condition `DEBUG`, so
`DEBUG || STAGING` also fails because it could permit a non-debug build.
You can change the matcher to check other conditions used in your project.

Keep `DEBUG` out of release build settings and use runtime tests to check how
the setting affects the app's connections.

## Read nested and alternative branches

`compilationBranches` lists the containing branches from the outermost branch
inwards. Each branch has a `condition` and `precedingConditions` for
earlier branches in the same chain:

```swift
#if STAGING
useStaging()
#elseif DEBUG
useDevelopment()
#else
useProduction()
#endif
```

For `useDevelopment()`, the condition is `DEBUG` and the preceding conditions
are `["STAGING"]`. That branch applies when `DEBUG` is true and `STAGING` is
false. The final branch has a `nil` condition and preceding conditions of
`["STAGING", "DEBUG"]`, both of which must be false.

You can check every branch, including code for other platforms, without
evaluating its condition for the current build. A compiler-index query covers
the configuration used to produce the index.

## Check a declaration's context

You can find the branches around a declaration by checking its location
against a file's branch list. This example saves the list in a local variable
to reuse it for each class:

```swift
let branches = file.compilationBranches
let contexts = file.classes.map { declaration in
  branches.filter { $0.contains(declaration.location) }
}
```

Each array in `contexts` contains the branches around the corresponding class
and is empty for a class outside a conditional block. You can use
`codebase.compilationBranches` when a rule checks the directives themselves,
such as the permitted condition names in a project.

The CLI supports these queries too. See <doc:InspectingExpressions> for
expression and assignment checks and <doc:AdvancedRules> for compiler-index
queries.
