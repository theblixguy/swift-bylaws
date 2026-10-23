# Formatting source

Describe a layout with captured source elements and apply it as a correction.

## Overview

You can write formatting rules in `Bylaws.swift` or Swift Testing. Use a
selection's `violations` closure to propose the desired source. Bylaws reports
a violation when a proposal changes the original bytes and attaches the edit
as its correction. A normal run keeps the files unchanged.

## Arrange attributes

This portable rule sorts attributes alphabetically and puts them together on
the line before the class declaration:

```swift
import Bylaws

nonisolated let app = Codebase(root: .automatic(), including: ["Sources/**"])

nonisolated let rules: [Rule] = [
  Rule("attributes", "Class attributes use alphabetical order") {
    try await app.classes.violations("Order attributes on one line") { declaration in
      let attributes = declaration.attributes
      if !attributes.isEmpty {
        try attributes.replacement {
          Line { attributes.sorted { $0.name < $1.name } }
        }
      }
    }
  },
]
```

The layout for `@Observable` and `@MainActor` is:

```swift
@MainActor @Observable
class Screen {}
```

Use `>` for descending order, or write your own comparison. A comparison must
give a consistent order. Elements that compare equally keep their original
order. The builder also takes collections returned by `filter` and source
elements emitted by `if` and `for` statements.

To put each attribute on its own line, change the replacement body to:

```swift
for attribute in attributes.sorted(by: { $0.name < $1.name }) {
  Line { attribute }
}
```

A replacement must emit every input element exactly once. Filtering a group
inside the builder is useful when the remaining groups emit the other
elements. An omitted or repeated element throws an error.

## Control the layout

| Operation | Behaviour |
| --- | --- |
| `Line { ... }` | Puts the enclosed source on one physical line, separate from surrounding code. Rejects source with physical line breaks. |
| `Newline()` | Requests a line break between source elements or at a list boundary. |
| `BlankLine()` | Separates non-empty output with an empty line. Repeated requests collapse, and empty sections add no leading or trailing blank lines. |
| `Indent { ... }` | Adds one indentation level after a line break, including a requested break before the first element. |
| `Wrap(width: 100) { ... }` | Wraps at permitted boundaries when the next element would exceed the width. |
| `Break()` | Adds an optional break, rendered as a space when the content fits. |
| `Align { ... }` | Aligns continuation lines to the start of its enclosed layout. |

A source list supplies its normal separators and break positions. An argument
list retains commas, while attributes use spaces. `Wrap` uses these break
positions without an explicit `Break` between each element. A single element
can exceed the width when it has no permitted internal break.

Wrapping defaults to 100 characters. Indentation comes from the source, with
two spaces used when no indentation can be inferred. Line endings retain the
source's LF, CRLF or CR spelling. Width counts characters and expands tabs to
eight-column stops. Use `SourceLayout { ... }` to construct a layout value
that another builder can emit.

## Wrap call arguments

This rule keeps the leading unlabelled arguments together and puts each
remaining argument on its own line:

```swift
Rule("call-arguments", "Log arguments use separate lines") {
  try await app.calls.named("logger.write")
    .violations("Wrap labelled arguments") { call in
      if call.arguments.count > 1 {
        let leading = call.arguments.prefix { $0.label == nil }
        try call.arguments.replacement {
          Line { leading }
          for argument in call.arguments.dropFirst(leading.count) {
            Line { argument }
          }
        }
      }
    }
}
```

The list supplies the commas and indentation. Use `Align` with `Wrap` to
preserve the first argument's position and align the continuation lines:

```swift
try call.arguments.replacement {
  Align {
    Wrap(width: 80) { call.arguments }
  }
}
```

A nested list replacement can appear in the outer builder in place of its
containing element. For example, an edit to array elements can wrap the array
within its argument. Each containing element must appear once, including
when it contains a nested edit. Use `Newline()` before the first element when
the list must start on a new line, or after the last element when the closing
parenthesis must start on a new line.

## Select source and whitespace

You can use the same operations on attributes, modifiers, members, statements,
parameters, enum case elements and array or dictionary elements. Use a
complete list for attributes, modifiers and comma-separated elements. Member
and statement lists can be consecutive regions within a larger list. A
collection of properties or functions from several files is not one editable list.

`SourceNode.members` and `SourceNode.statements` expose direct children in
source order. A member's `property` projection returns a `Property` when the
member declares one binding. You can inspect its visibility, attributes and
other properties in your ordering logic. An attribute's `argument` projection
returns its single unlabelled expression, and
`hasAttribute("Environment", argument: \.isKeyPath)` checks that form directly.

An empty collection has no source span to replace. Check `isEmpty` before
proposing a layout for a list that may be empty.

You can change adjacent whitespace without rebuilding a list:

```swift
try declaration.spacing.before.replacement(with: .blankLine)
try declaration.spacing.after.replacement(with: .newline)
```

The available values are `.none`, `.space`, `.newline` and `.blankLine`.
The projections stop at neighbouring comments. Replacements preserve line
endings and indentation, and reject a change that would put following code
inside a line comment.

## Report from Swift Testing

Use the same selection and replacement body in a test, then report the result:

```swift
import Bylaws
import Testing

@Test("Class attributes use alphabetical order")
func orderedAttributes() async throws {
  let app = Codebase(root: .automatic(), including: ["Sources/**"])
  let violations = try await app.classes.violations("Order attributes on one line") { declaration in
    let attributes = declaration.attributes
    if !attributes.isEmpty {
      try attributes.replacement {
        Line { attributes.sorted { $0.name < $1.name } }
      }
    }
  }

  violations.report()
}
```

Run `bylaws lint --autocorrect` to apply corrections and run the rules again.
See <doc:CorrectingSource> for previewing edits and selecting rules or tests.

## Limits

A layout preserves captured source elements. Use the source replacement API
to change a name, literal or other content. Layout checks reject foreign source,
missing elements and unclear comment ownership. Conditional-compilation
boundaries and formatting-control comments also stop rearrangement.
The builder takes one nested edit per containing element. Several nested
edits for the same element are rejected.

A multi-line element must have a common outer indentation on its non-empty
continuation lines for a layout to change its indentation. A partial change
can change a multiline string's value, so the layout rejects it.

Reordering source can change behaviour. Stored-property order can affect
memberwise initialisers, parameter order changes call sites and enum case
order can change implicit raw values. Attribute order can change
[property-wrapper composition](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0258-property-wrappers.md#composition-of-property-wrappers).
The rule author must choose where an ordering policy is safe. Syntax
validation does not establish semantic equivalence.

Portable layout closures are synchronous and can throw. Their comparisons,
conditions and helpers use the portable Swift subset. Swift Testing rules can
use the full language. The correction checks in <doc:CorrectingSource> apply
to both surfaces.
