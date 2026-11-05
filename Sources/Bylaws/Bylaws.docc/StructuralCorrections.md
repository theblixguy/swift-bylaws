# Change source structure

Insert list elements and replace wrappers while retaining the code inside them.

## Overview

You can use `Insert`, `Remove`, `Replace`, `Unwrap` and `Layout` together in a
correction. Each operation also has a value or method form, so a helper can
return a correction without a result builder.

The examples below work in `Bylaws.swift` and Swift Testing. Run
`bylaws lint --autocorrect` to apply their fixes and check the rules again.
<doc:CorrectingSource> explains how to select rules and preview the changes.

## Insert an attribute

This rule adds `@MainActor` to store classes. Use it where your project's store
API belongs to the main actor.

### Bylaws.swift

```swift
import Bylaws

nonisolated let app = Codebase(root: .automatic(), including: ["Sources/**"])

nonisolated let rules: [Rule] = [
  Rule("store-isolation", "Stores use MainActor") {
    try await app.classes.suffixed("Store")
      .violations(of: .hasAttribute("MainActor"))
      .withFix { context in
        try Insert("@MainActor", into: context.offender.attributeList, at: .start)
      }
  },
]
```

### Swift Testing

```swift
import Bylaws
import Testing

@Test("Stores use MainActor")
func storeIsolation() async throws {
  let app = Codebase(root: .automatic(), including: ["Sources/**"])
  let violations = try await app.classes.suffixed("Store")
    .violations(of: .hasAttribute("MainActor"))
    .withFix { context in
      try Insert("@MainActor", into: context.offender.attributeList, at: .start)
    }

  violations.report(ruleID: "store-isolation")
}
```

An `attributeList` retains its declaration when it is empty. The corresponding
`modifierList`, `argumentList`, `memberList` and `statementList` properties give
you the same insertion support for those lists. The inserted text must contain
one element of the list's kind. Bylaws supplies its separators.

You can use the method form in either fix closure:

```swift
try context.offender.attributeList.inserting("@MainActor", at: .start)
```

Use `.end` to append an element, which is the default. Use `.index(index)` to
insert before an existing element.

You can combine an insertion with `Layout`. The `.start` and `.end` positions
refer to the final order, while an indexed insertion stays before its captured
element after reordering. A grouping predicate runs on the original elements,
and each inserted element uses its neighbour's layout.

You can remove an element and its separator with either form:

```swift
try Remove(element)
try list.removing(element)
```

A removal that would discard an attached comment produces a violation without
a fix.

## Flatten an else-if branch

This rule changes `else { if ... }` to `else if ...` when the branch contains
one conditional and its context permits the change.

### Bylaws.swift

```swift
import Bylaws

nonisolated let app = Codebase(root: .automatic(), including: ["Sources/**"])

nonisolated let rules: [Rule] = [
  Rule("else-if", "Single conditional else branches use else if") {
    try await app.ifExpressions.violations("Use else if") { conditional in
      try Unwrap(conditional.elseBody, containingOnly: .ifExpression)
    }
  },
]
```

### Swift Testing

```swift
import Bylaws
import Testing

@Test("Single conditional else branches use else if")
func elseIfBranches() async throws {
  let app = Codebase(root: .automatic(), including: ["Sources/**"])
  let violations = try await app.ifExpressions.violations("Use else if") { conditional in
    try Unwrap(conditional.elseBody, containingOnly: .ifExpression)
  }

  violations.report(ruleID: "else-if")
}
```

For example, the rule changes this function:

```swift
func update() {
  if isReady {
    start()
  } else {
    if canRetry {
      retry()
    }
  }
}
```

The result is:

```swift
func update() {
  if isReady {
    start()
  } else if canRetry {
    retry()
  }
}
```

You can use `try body.unwrapped(containingOnly: .ifExpression)` on an existing
else body for the method form. A missing branch or a branch with other
statements produces no violation.

A result builder can assign different meanings to the two branch structures.
`Unwrap` reports unknown applicability when it cannot establish an ordinary
statement context. This includes some member functions, getters and closures
whose builder context could come from another declaration. Restrict the
selection to code whose context can be established, or define an explicit
replacement after checking the builder's behaviour.

`Unwrap` also checks redundant expression and type parentheses. It retains
parentheses that preserve expression grouping. Removing a `return`, a `do`
block, a call or an immediately invoked closure needs more information about
types, scope or effects, so those forms produce an undetermined result.

## Retain an expression from a call

Suppose your project has a `legacyIdentity` function that returns its argument
without changing its value or type. Once callers can use the argument directly,
this rule removes calls with one argument.

### Bylaws.swift

```swift
import Bylaws

nonisolated let app = Codebase(root: .automatic(), including: ["Sources/**"])

nonisolated let rules: [Rule] = [
  Rule("legacy-identity", "Use values directly") {
    try await app.calls.named("legacyIdentity")
      .violations("Use the argument directly") { call in
        if call.arguments.count == 1 {
          let argument = try call.arguments.only()
          try Replace(call) {
            try argument.expressionSource
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

@Test("Use values directly")
func removeLegacyIdentity() async throws {
  let app = Codebase(root: .automatic(), including: ["Sources/**"])
  let violations = try await app.calls.named("legacyIdentity")
    .violations("Use the argument directly") { call in
      if call.arguments.count == 1 {
        let argument = try call.arguments.only()
        try Replace(call) {
          try argument.expressionSource
        }
      }
    }

  violations.report(ruleID: "legacy-identity")
}
```

The replacement for `legacyIdentity(left + right) * scale` is
`(left + right) * scale`. Corrections to `left` or `right` can apply within the
retained expression. An edit to the discarded call name conflicts with this
replacement.

You can pass the retained source directly or request an edit from its source
slice:

```swift
try Replace(call, with: argument.expressionSource)
try call.source.replacement(with: argument.expressionSource)
```

`Replace` retains an unavailable result when it cannot prepare the correction.
The source slice's `replacement` method returns an edit and throws in that case.

Use captured source to retain its expression grouping. Passing
`argument.expressionSource.text` instead requests an exact text replacement,
which leaves grouping to the rule author. A call-name match also leaves symbol
identity, overloads, evaluation effects and type changes to the rule author.

## Keep a scope around retained statements

After establishing that a branch should replace its conditional, you can keep
its statements inside a `do` block:

```swift
try Replace(conditional) {
  Scope {
    conditional.body.statements
  }
}
```

The value form uses the same replacement:

```swift
let contents = SourceReplacement(sources: conditional.body.statements)
let scope = Scope(replacement: contents)
try Replace(conditional, with: scope.replacement)
```

The `do` block keeps local declarations and `defer` in a lexical scope. The
rule must account for condition bindings, availability checks, control flow
and result-builder behaviour before removing the conditional.

Captured replacements must retain complete syntax nodes from inside their
target. Bylaws declines a replacement that would discard comments or
formatting directives. A target that contains a multiline string also leaves
the fix unavailable.
<doc:CorrectingSource#Correction-checks-and-limits> describes the checks that
apply to every correction.
