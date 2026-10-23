# Formatting cookbook

Define layouts from captured source elements, from attribute order to nested
call arguments.

## Overview

Each recipe includes a complete `Bylaws.swift` rule and a Swift Testing rule.
Use one version at a time. Both produce corrections for `bylaws lint
--autocorrect`, and an already-correct layout produces no violation.

<doc:FormattingSource> explains the builder operations and supported lists.
<doc:CorrectingSourceCookbook> covers content changes, token and comment
edits, multiple files and correction tests. Start with a narrow selection and
add the syntax forms your project uses.

## Order attributes

This rule puts `Observable` first and keeps the other attributes in their
source order. The comparison gives `Observable` priority without assigning
numbered categories.

### Bylaws.swift

```swift
import Bylaws

nonisolated let app = Codebase(root: .automatic(), including: ["Sources/**"])

nonisolated let rules: [Rule] = [
  Rule("observable-first", "Observable precedes other attributes") {
    try await app.classes
      .violations("Observable precedes other attributes") { declaration in
        let attributes = declaration.attributes
        if !attributes.isEmpty {
          try attributes.replacement {
            Line {
              attributes.sorted { lhs, rhs in
                lhs.name == "Observable" && rhs.name != "Observable"
              }
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

@Test("Observable precedes other attributes")
func observableFirst() async throws {
  let app = Codebase(root: .automatic(), including: ["Sources/**"])
  let violations = try await app.classes
    .violations("Observable precedes other attributes") { declaration in
      let attributes = declaration.attributes
      if !attributes.isEmpty {
        try attributes.replacement {
          Line {
            attributes.sorted { lhs, rhs in
              lhs.name == "Observable" && rhs.name != "Observable"
            }
          }
        }
      }
    }

  violations.report(ruleID: "observable-first")
}
```

The result for the two named attributes is:

```text
@Observable @MainActor
class Screen {}
```

For alphabetical order, use `attributes.sorted { $0.name < $1.name }` in
either version. Use `>` for descending order, or compare another attribute
property. Equal elements retain their original order. Attribute order can
change property-wrapper composition, so apply an ordering policy only where it
is safe.

<doc:FormattingSource#Arrange-attributes> has a complete alphabetical rule.

## Group a leading run of properties

This rule groups the leading properties of a struct as environment key paths,
other environment values, state and constants. Blank lines separate the
environment, state and constant groups. Private constants precede other
constants.

The selection stops at a member it cannot classify. That member and every
following member retain their position. It also stops at several bindings in
one declaration or an attribute combination the rule does not recognise. Every
property in the selected run appears once in the layout.

### Bylaws.swift

```swift
import Bylaws

nonisolated let app = Codebase(root: .automatic(), including: ["Sources/**"])

nonisolated let rules: [Rule] = [
  Rule("property-groups", "Leading properties use project order") {
    try await app.syntaxNodes(of: .structDeclaration)
      .violations("Leading properties use project order") { declaration in
        let properties = declaration.members.prefix { member in
          let isEnvironment = member.hasAttribute("Environment")
          let isState = member.hasAttribute("State")
          let oneAttribute = member.attributes.count == 1
          let isWrapped = oneAttribute && (isEnvironment || isState)
          let isConstant = member.property?.isConstant == true
          let isPlainConstant = member.attributes.isEmpty && isConstant
          return member.property != nil && (isWrapped || isPlainConstant)
        }
        if !properties.isEmpty {
          let environment = properties.filter { $0.hasAttribute("Environment") }
          let state = properties.filter { $0.hasAttribute("State") }
          let constants = properties.filter(\.attributes.isEmpty)
          try properties.replacement {
            environment.filter { $0.hasAttribute(
              "Environment",
              argument: \.isKeyPath
            ) }
            environment.filter { !$0.hasAttribute(
              "Environment",
              argument: \.isKeyPath
            ) }
            BlankLine()
            state
            BlankLine()
            constants.filter { $0.property?.visibility == .private }
            constants.filter { $0.property?.visibility != .private }
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

@Test("Leading properties use project order")
func propertyGroups() async throws {
  let app = Codebase(root: .automatic(), including: ["Sources/**"])
  let violations = try await app.syntaxNodes(of: .structDeclaration)
    .violations("Leading properties use project order") { declaration in
      let properties = declaration.members.prefix { member in
        let isEnvironment = member.hasAttribute("Environment")
        let isState = member.hasAttribute("State")
        let oneAttribute = member.attributes.count == 1
        let isWrapped = oneAttribute && (isEnvironment || isState)
        let isConstant = member.property?.isConstant == true
        let isPlainConstant = member.attributes.isEmpty && isConstant
        return member.property != nil && (isWrapped || isPlainConstant)
      }
      if !properties.isEmpty {
        let environment = properties.filter { $0.hasAttribute("Environment") }
        let state = properties.filter { $0.hasAttribute("State") }
        let constants = properties.filter(\.attributes.isEmpty)
        try properties.replacement {
          environment.filter { $0.hasAttribute(
            "Environment",
            argument: \.isKeyPath
          ) }
          environment.filter { !$0.hasAttribute(
            "Environment",
            argument: \.isKeyPath
          ) }
          BlankLine()
          state
          BlankLine()
          constants.filter { $0.property?.visibility == .private }
          constants.filter { $0.property?.visibility != .private }
        }
      }
    }

  violations.report(ruleID: "property-groups")
}
```

The rule retains order within each group. It treats every non-key-path
`Environment` argument as part of the second group. If your project permits
other argument forms, add the corresponding condition before including them.

Stored-property order can affect initialisation and memberwise initialisers.
The rule author must decide which declarations can be reordered. An
unclassified member stops this recipe, rather than being moved to a catch-all
group.

## Separate adjacent statements

This rule places a blank line between a binding and a call, and between a
throwing statement and an adjacent binding or call. Consecutive nonthrowing bindings keep
their existing separation.

### Bylaws.swift

```swift
import Bylaws

nonisolated let app = Codebase(root: .automatic(), including: ["Sources/**"])

nonisolated let rules: [Rule] = [
  Rule("statement-gaps", "Bindings and throwing calls use blank lines") {
    try await app.syntaxNodes(of: .codeBlock)
      .violations("Bindings and throwing calls use blank lines") { block in
        let statements = block.statements
        if !statements.isEmpty {
          try statements.replacement {
            for index in statements.indices {
              if index > statements.startIndex {
                let previous = statements[index - 1]
                let current = statements[index]
                let previousBinding = previous.kind == .variableDeclaration
                let currentBinding = current.kind == .variableDeclaration
                let previousHasCall = previous.contains(.functionCall)
                let currentHasCall = current.contains(.functionCall)
                let previousCall = !previousBinding && previousHasCall
                let currentCall = !currentBinding && currentHasCall
                let previousThrows = previous.contains(.tryExpression)
                let currentThrows = current.contains(.tryExpression)
                let bindingAndCall = previousBinding && currentCall
                  || currentBinding && previousCall
                let throwingAndStatement = previousThrows &&
                  (currentBinding || currentCall)
                  || currentThrows && (previousBinding || previousCall)
                if bindingAndCall || throwingAndStatement {
                  BlankLine()
                }
              }
              statements[index]
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

@Test("Bindings and throwing calls use blank lines")
func statementGaps() async throws {
  let app = Codebase(root: .automatic(), including: ["Sources/**"])
  let violations = try await app.syntaxNodes(of: .codeBlock)
    .violations("Bindings and throwing calls use blank lines") { block in
      let statements = block.statements
      if !statements.isEmpty {
        try statements.replacement {
          for index in statements.indices {
            if index > statements.startIndex {
              let previous = statements[index - 1]
              let current = statements[index]
              let previousBinding = previous.kind == .variableDeclaration
              let currentBinding = current.kind == .variableDeclaration
              let previousHasCall = previous.contains(.functionCall)
              let currentHasCall = current.contains(.functionCall)
              let previousCall = !previousBinding && previousHasCall
              let currentCall = !currentBinding && currentHasCall
              let previousThrows = previous.contains(.tryExpression)
              let currentThrows = current.contains(.tryExpression)
              let bindingAndCall = previousBinding && currentCall
                || currentBinding && previousCall
              let throwingAndStatement = previousThrows &&
                (currentBinding || currentCall)
                || currentThrows && (previousBinding || previousCall)
              if bindingAndCall || throwingAndStatement {
                BlankLine()
              }
            }
            statements[index]
          }
        }
      }
    }

  violations.report(ruleID: "statement-gaps")
}
```

For example:

```text
let request = try makeRequest()

await record(request)

try await save(request)

let count = 1
let limit = 2
```

`contains` includes the node itself and all descendants, including nested
closures and declarations. This recipe therefore treats a statement with a
nested call or `try` as containing one. Choose a narrower predicate if your
policy concerns only the outer expression.

## Wrap at a width

This rule wraps at argument boundaries to fit 80 characters and aligns
continuation lines with the first argument.

### Bylaws.swift

```swift
import Bylaws

nonisolated let app = Codebase(root: .automatic(), including: ["Sources/**"])

nonisolated let rules: [Rule] = [
  Rule("argument-width", "Call arguments fit 80 characters") {
    try await app.calls.violations("Call arguments fit 80 characters") { call in
      if !call.arguments.isEmpty {
        try call.arguments.replacement {
          Align {
            Wrap(width: 80) { call.arguments }
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

@Test("Call arguments fit 80 characters")
func argumentWidth() async throws {
  let app = Codebase(root: .automatic(), including: ["Sources/**"])
  let violations = try await app.calls
    .violations("Call arguments fit 80 characters") { call in
      if !call.arguments.isEmpty {
        try call.arguments.replacement {
          Align {
            Wrap(width: 80) { call.arguments }
          }
        }
      }
    }

  violations.report(ruleID: "argument-width")
}
```

Width counts characters in the source line, with tabs expanded to eight-column
stops. An indivisible argument can exceed the limit. The rule can break
between arguments, but it does not shorten a string or rewrite an expression
to make it fit.

## Store and indent a layout

A `SourceLayout` value stores a layout description that another builder can
emit. This rule stores the argument sequence, then puts it inside an indented,
width-limited layout. It applies only to calls named `send`.

`Indent` adds one level to the list's inferred indentation. With the default
two-space level, the example below uses four spaces for arguments. `Break`
supplies an optional break that becomes a space when the content fits.
Ordinary argument lists already supply these break positions, so the explicit
breaks show how to compose a layout rather than a step every rule must take.

### Bylaws.swift

```swift
import Bylaws

nonisolated let app = Codebase(root: .automatic(), including: ["Sources/**"])

nonisolated let rules: [Rule] = [
  Rule("reusable-argument-layout", "Send arguments use indented layout") {
    try await app.calls.named("send")
      .violations("Send arguments use indented layout") { call in
        if !call.arguments.isEmpty {
          let layout = SourceLayout {
            for argument in call.arguments {
              argument
              Break()
            }
          }
          try call.arguments.replacement {
            Indent {
              Newline()
              Wrap(width: 80) { layout }
            }
            Newline()
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

@Test("Send arguments use indented layout")
func reusableArgumentLayout() async throws {
  let app = Codebase(root: .automatic(), including: ["Sources/**"])
  let violations = try await app.calls.named("send")
    .violations("Send arguments use indented layout") { call in
      if !call.arguments.isEmpty {
        let layout = SourceLayout {
          for argument in call.arguments {
            argument
            Break()
          }
        }
        try call.arguments.replacement {
          Indent {
            Newline()
            Wrap(width: 80) { layout }
          }
          Newline()
        }
      }
    }

  violations.report(ruleID: "reusable-argument-layout")
}
```

For `let result = send(first: 1, second: 2)`, the result is:

```text
let result = send(
    first: 1, second: 2
)
```

The layout retains captured source identity. Reuse its description within the
same correction context, and emit each selected argument once. A layout value
from another source list cannot supply replacement arguments for this list.

## Format a nested array argument

This rule keeps leading unlabelled logging arguments together, puts each
labelled argument on a new line and expands array arguments. A nested array
correction stands in for its containing argument in the outer layout.

### Bylaws.swift

```swift
import Bylaws

nonisolated let app = Codebase(root: .automatic(), including: ["Sources/**"])

nonisolated let rules: [Rule] = [
  Rule("logging-layout", "Logging arguments use project layout") {
    try await app.calls.named("logger.write")
      .violations("Logging arguments use project layout") { call in
        if !call.arguments.isEmpty {
          let leading = call.arguments.prefix { $0.label == nil }
          try call.arguments.replacement {
            if !leading.isEmpty {
              Line { leading }
            }
            for argument in call.arguments.dropFirst(leading.count) {
              if let elements = argument.expression?.arrayElements,
                 !elements.isEmpty
              {
                try elements.replacement {
                  for element in elements {
                    Line { element }
                  }
                }
              } else {
                Line { argument }
              }
            }
            Newline()
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

@Test("Logging arguments use project layout")
func loggingLayout() async throws {
  let app = Codebase(root: .automatic(), including: ["Sources/**"])
  let violations = try await app.calls.named("logger.write")
    .violations("Logging arguments use project layout") { call in
      if !call.arguments.isEmpty {
        let leading = call.arguments.prefix { $0.label == nil }
        try call.arguments.replacement {
          if !leading.isEmpty {
            Line { leading }
          }
          for argument in call.arguments.dropFirst(leading.count) {
            if let elements = argument.expression?.arrayElements,
               !elements.isEmpty
            {
              try elements.replacement {
                for element in elements {
                  Line { element }
                }
              }
            } else {
              Line { argument }
            }
          }
          Newline()
        }
      }
    }

  violations.report(ruleID: "logging-layout")
}
```

For a call with an array argument, the result is:

```text
logger.write(
  .info, "Ready",
  category: "Transfer",
  tags: [
    "ready",
    "cached"
  ]
)
```

An empty array stays with its argument because it has no element span to
replace. `Line` rejects an element containing physical line breaks. This
recipe therefore stops rather than flattening a multiline expression. Use
`Wrap` or emit the original element when your policy permits those forms.

## Lay out another syntax list

The same builder can operate on a captured condition list. This rule wraps
comma-separated conditions at 80 characters. It keeps each condition intact
and retains its source order.

### Bylaws.swift

```swift
import Bylaws

nonisolated let app = Codebase(root: .automatic(), including: ["Sources/**"])

nonisolated let rules: [Rule] = [
  Rule("condition-width", "Conditions fit 80 characters") {
    try await app.syntaxNodes(of: .conditionList)
      .violations("Conditions fit 80 characters") { list in
        let conditions = list.elements
        if !conditions.isEmpty {
          try conditions.replacement {
            Align {
              Wrap(width: 80) { conditions }
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

@Test("Conditions fit 80 characters")
func conditionWidth() async throws {
  let app = Codebase(root: .automatic(), including: ["Sources/**"])
  let violations = try await app.syntaxNodes(of: .conditionList)
    .violations("Conditions fit 80 characters") { list in
      let conditions = list.elements
      if !conditions.isEmpty {
        try conditions.replacement {
          Align {
            Wrap(width: 80) { conditions }
          }
        }
      }
    }

  violations.report(ruleID: "condition-width")
}
```

The list API also covers generic parameters and arguments, generic
requirements, inherited types, closure parameters and captures, tuple elements
and switch lists. Select a list kind, read its `elements` and define the
layout. A list keeps its own punctuation and ownership rules.

Layouts preserve the selected elements. A rule that adds an argument, removes
an accessor, changes a literal or rewrites an operator needs a source
replacement. Start with the smallest captured source span, and use the
correction checks and tests in <doc:CorrectingSourceCookbook>.
