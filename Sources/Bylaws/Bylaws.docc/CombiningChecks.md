# Combine checks and match declaration members

Check several requirements in one rule and match a declaration's members.

## Overview

You can put related checks in one `Rule` body, such as requiring a view model
to be final and keep its properties out of the public API. If a check fails,
the diagnostic identifies the condition and the declaration's source location.

## Put related checks in one rule

This rules file checks the classes whose names end in `ViewModel`:

```swift
import Bylaws
import Testing

let app = Codebase(including: ["Sources/**"])

let rules = Array {
  Rule("view-models", "View models follow project rules") {
    let viewModels = try await app.classes.suffixed("ViewModel")
    viewModels.violations(of: .isFinal)
    viewModels.violations(
      of: Matcher<Class>.none(\.properties, matching: .isPublic)
    )
  }
}
```

Both checks run even when the first reports a violation.

The checks share the rule's ID, enforcement level, hint and baseline settings.
A baseline entry for a declaration applies to every check in that rule, so use
separate rules when exceptions should apply to one check alone. You can inspect
individual results with `try await rule.findings().checks` or get all failures
with `try await rule.violations()`.

The total counts checks rather than declarations, so checking one declaration
twice adds two to the total. A rule with no checks produces a warning.

## Check declaration members

The `all`, `any` and `none` matchers take a key path to a collection of members
and a matcher for those members. For example, a project can require each
repository to have an asynchronous function:

```swift
let hasAsyncFunction = Matcher<Class>.any(\.functions, matching: .isAsync)
let repositories = try await app.classes.suffixed("Repository")
let failures = repositories.violations(of: hasAsyncFunction)
```

Use `all` when every selected member must pass and `none` when a matching
member is forbidden:

```swift
let hasNoPublicProperties = Matcher<Class>.none(
  \.properties,
  matching: .isPublic
)
```

For an empty collection, `all` and `none` pass, while `any` fails. To require
at least one function and require all functions to be asynchronous, combine
the member check with a count check:

```swift
let hasFunctions = Matcher<Class>("have at least one function") {
  !$0.functions.isEmpty
}

let hasAsyncFunctions = hasFunctions
  && Matcher<Class>.all(\.functions, matching: .isAsync)
```

A failed `all` check points to the first member that fails, while a failed
`none` check points to the first forbidden member. If `any` finds no match,
the failure points to the containing declaration. You can combine these
matchers with `!`, `&&` and `||` or use them inside other member matchers.

## Use Boolean properties as checks

A Boolean key path can replace a closure that reads one property:

```swift
let classes = try await app.classes
let nonFinalClasses = classes.violations(of: \.isFinal)
let finalClasses = classes.violations(matching: \.isFinal)
let isFinal = Matcher<Class>(\.isFinal)
```

`of:` reports declarations where the property is false, while `matching:`
reports those where it is true. Prefer a named matcher such as `.isFinal` when
the diagnostic must name the condition. Swift can omit computed property names
from key-path descriptions, which can make the resulting message less useful.

## Add checks conditionally

Rule bodies support local values, conditions and loops:

```swift
let requireDocumentation = true

let rules = Array {
  Rule("models") {
    let classes = try await app.classes
    classes.violations(of: .isFinal)
    if requireDocumentation {
      classes.violations(of: .hasDocumentation)
    }
  }
}
```

Each standalone expression in a rule body must produce a check result. Store a
selection in a local `let` when you want to use it in several checks. An
explicit `return` uses ordinary closure behaviour and returns only that result.

You can also use `RuleResults` in a helper to combine results from checks on
different declaration types:

```swift
let classes = try await app.classes
let functions = try await app.functions
let results = RuleResults(
  classes.violations(of: .isFinal),
  functions.violations(of: .isAsync)
)
```

## Build rule and layer lists

You can use `Array { ... }` to create a `[Rule]` array from individual rules,
existing arrays or rules added through conditions and loops:

```swift
let rules = Array {
  for suffix in ["ViewModel", "Presenter"] {
    Rule(suffix + "-final") {
      try await app.classes.suffixed(suffix).violations(of: .isFinal)
    }
  }
}
```

Use a distinct ID for each rule, as the example does with `suffix + "-final"`.

`Layering` has a similar initialiser:

```swift
let layers = Layering {
  Layer("Domain", files: ["Sources/Domain/**"])
  Layer("Data", files: ["Sources/Data/**"], mayImport: ["Domain"])
  Layer("App", files: ["Sources/App/**"], mayImport: ["Domain", "Data"])
}
```

For a fixed list of layers, you can pass an array or individual `Layer` values
to `Layering(...)` instead.

## Run these rules from the CLI

The CLI supports combined rule bodies, member matchers, Boolean key-path
checks, `RuleResults`, rule-list builders and layer-list builders. Put these
rules in a `[Rule]` binding, as in the examples above. Standalone `Rule` and
`Override` declarations take one query per rule body.

In a portable `for` loop, bind each element of an array, set or selection to
one name. Custom builders, `for await`, pattern-matching loops and availability
conditions need a compiled test target. See <doc:RunningRulesFromTheCLI> for
the supported Swift subset and the steps to run a rules file as tests.
