# Formatting source

Describe a layout with captured source elements and apply it as a correction.

## Overview

You can write formatting rules in `Bylaws.swift` or Swift Testing. Use a
selection's `violations` closure and `Layout` to describe the desired source.
Bylaws reports a violation when a proposal changes the source and attaches the
edit as its correction. A normal run keeps the files unchanged.

<doc:FormattingCookbook> has complete recipes for custom ordering, property
groups, statement spacing, wrapping and nested layouts in both rule forms.

## Arrange attributes

You can sort attributes alphabetically and put them together on the line before
the class declaration:

```swift
import Bylaws

nonisolated let app = Codebase(root: .automatic(), including: ["Sources/**"])

nonisolated let rules: [Rule] = [
  Rule("attributes", "Class attributes use alphabetical order") {
    try await app.classes.violations("Order attributes on one line") { declaration in
      let attributes = declaration.attributes
      try Layout(attributes) {
        Line(attributes.sorted { $0.name < $1.name })
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

To put each attribute on its own line, use `Lines` and request a break at each
end of the list:

```swift
Lines(attributes.sorted { $0.name < $1.name }, boundaries: .newline)
```

When an explicit layout emits source, it must include every input element
exactly once. You can filter a collection inside the builder if its other
expressions emit the remaining elements. An omitted or repeated element throws
an error.

Use `Group { ... }` to assign each input element to the first matching group.
Groups appear in the written order and retain source order within each group.
Add `.sorted { ... }` to give a group its own comparison. An unmatched element
stays in place and divides the list into separate regions. Each region keeps
its elements on the same side of that element.

A grouped layout emits its input elements automatically. Use `BlankLine()` or
`Newline()` between groups to set their separation. Empty groups add no blank
lines. A layout uses either explicit elements or automatic groups.

Use `Group(\.property) { $0.isConstant }` to group members through an optional
projection. A missing property leaves the member for later groups. For a list
of properties, `Group(\.isConstant)` uses the Boolean property directly.
You can also pass a matcher, such as `Group(.hasAttribute("State"))`.

## Control the layout

| Operation | Behaviour |
| --- | --- |
| `Lines(elements)` | Separates the elements with line breaks and permits multiline elements. Pass `boundaries: .newline` to start and end the list on separate lines. |
| `Joined(elements)` | Keeps the elements together with their normal separators. Permits multiline contents and forms one item inside `Lines`. An empty sequence adds no output. |
| `Line { ... }` | Puts the enclosed source on one physical line, separate from surrounding code. Rejects source with physical line breaks. |
| `Newline()` | Requests a line break between source elements or at a list boundary. |
| `BlankLine()` | Separates non-empty output with an empty line. Repeated requests collapse, and empty sections add no leading or trailing blank lines. |
| `Group { ... }` | Assigns each input element to its first matching group. Retains source order within the group unless `.sorted { ... }` supplies a comparison. |
| `Indent { ... }` | Adds one indentation level after a line break, including a requested break before the first element. |
| `Wrap(width: 100) { ... }` | Wraps at permitted boundaries when the next element would exceed the width. |
| `Break()` | Adds an optional break, rendered as a space when the content fits. |
| `Align { ... }` | Aligns continuation lines to the start of its enclosed layout. |

A source list supplies its normal separators and break positions. An argument
list retains commas, while attributes use spaces. `Wrap` uses these break
positions without an explicit `Break` between each element. A single element
can exceed the width when it has no permitted internal break.

Wrapping defaults to 100 characters. An explicit layout infers space
indentation from source outside the replaced list, with two spaces used when
none can be inferred. Tabs use one tab per level. A grouped layout retains
each region's original indentation. Line endings retain the source's LF, CRLF
or CR spelling. Width counts characters and expands tabs to eight-column stops.
Each operation takes a collection or a builder closure. Use `SourceLayout { ... }`
to combine operations in a layout value. An empty input or empty layout leaves
the source unchanged, including when `Lines` requests outer line breaks.

## Use stored layouts

You can construct the same layout with values, then pass it to `Layout`:

```swift
let line = Line(attributes.sorted { $0.name < $1.name })
try Layout(attributes, layout: line)
```

`Line`, `Lines`, `Joined`, `Indent`, `Wrap` and `Align` also take a `layout:` value. You can
combine stored layouts with `SourceLayout([first, second])` and add `.newline`,
`.blankLine` or `.softBreak` where you want a boundary.

A `LayoutContent` value can hold grouping and spacing policies:

```swift
let groups: LayoutContent<SourceNode> = .sequence([
  .group(Group(\.property) { $0.isConstant && $0.visibility == .private }),
  .group(Group(\.property) { $0.isConstant })
])

try Layout(declaration.members) {
  groups
  BlankLine(before: { $0.name == "refresh" })
}
```

You can pass `groups` directly as `layout: groups`. A builder can include a
stored value alongside its own operations, as the spacing condition above
shows. Collection `.replacement { ... }` calls can also appear in a correction
closure.

## Wrap call arguments

This rule keeps the leading unlabelled arguments together and puts each
remaining argument on its own line. Its syntax query includes top-level calls:

```swift
Rule("call-arguments", "Call arguments use separate lines") {
  try await app.syntaxNodes(of: .functionCall)
    .violations("Wrap labelled arguments") { node in
      if let call = node.call, call.arguments.count > 1 {
        let leading = call.arguments.prefix { $0.label == nil }
        let remaining = call.arguments.dropFirst(leading.count)
        try Layout(call.arguments, when: .maximumLineLength(101...)) {
          Lines(boundaries: .newline) {
            Joined(leading)
            remaining
          }
        }
      }
    }
}
```

The list supplies the commas and indentation. To give every argument its own
line, use `Lines(call.arguments, boundaries: .newline)` as the layout body.

Use `Align` with `Wrap` to preserve the first argument's position and align the
continuation lines:

```swift
try Layout(call.arguments) {
  Align {
    Wrap(call.arguments, width: 80)
  }
}
```

Use `.applying` to attach corrections inside the selected elements. For example,
you can expand array and dictionary arguments along with the call:

```swift
try Layout(call.arguments) {
  Lines(call.arguments, boundaries: .newline)
}.applying(toEach: call.arguments.compactMap { $0.expression?.elements }) {
  Lines($0, boundaries: .newline)
}
```

An expression's `elements` projection returns an array's elements or a
dictionary's complete key-value entries. Other expressions return `nil`.
Empty arrays and dictionaries remain unchanged.

Attached corrections follow the containing layout's condition. They can change
the contents even when the containing layout's spacing already matches. Each
correction must stay inside an element retained by that layout. A grouping or
spacing policy retains its matched regions, so corrections outside those
regions must be separate operations. You can also pass a stored correction to
`.applying`. The `.applying(toEach:)` closure can return a stored `LayoutContent`
value or be a named function that returns one.

Layouts from different rules can format a nested call and its containing
statement or declaration together. Use `Newline()` before an element that
can span several lines. Use `Line` when the whole element must stay on one
physical line.

## Set a layout condition

`when: .maximumLineLength(101...)` applies a layout when the longest affected
source line exceeds 100 columns. You can use Swift ranges for other conditions:

| Condition | Longest affected line |
| --- | --- |
| `.maximumLineLength(50...)` | At least 50 columns |
| `.maximumLineLength(...50)` | At most 50 columns |
| `.maximumLineLength(..<50)` | Fewer than 50 columns |
| `.maximumLineLength(50..<100)` | Between 50 and 99 columns |

Use `!`, `&&` and `||` to negate or combine conditions. For a configurable strict
limit, use `when: !.maximumLineLength(...maximumWidth)`. Omit `when:`, or pass
`nil`, to apply the layout unconditionally. `Wrap(width:)` sets the desired
wrapping width independently of the condition.

The measurement includes surrounding text and the layout's position after any
containing layout moves it, before applying its own correction. A nested call
that fits on its new line can stay compact. A grouping or spacing policy
checks each affected region separately. To check the captured source directly,
use `source.hasLine(exceeding: 100, tabWidth: 8)`.

## Select source and whitespace

You can use the same operations on attributes, modifiers, members, statements,
parameters, enum case elements and array or dictionary elements. Use a
complete list for attributes, modifiers and comma-separated elements. Member
and statement lists can be consecutive regions within a larger list. A
collection of properties or functions from several files is not one editable
list.

You can select other syntax lists with `file.syntaxNodes(of:)` and use each
node's `elements` projection. For example,
`file.syntaxNodes(of: .genericRequirementList)` selects the lists in `where`
clauses. The supported kinds are:

| List | Syntax kind |
| --- | --- |
| Conditions | `.conditionList` |
| Generic clauses | `.genericParameterList`, `.genericArgumentList`, `.genericRequirementList` |
| Inheritance and primary associated types | `.inheritedTypeList`, `.primaryAssociatedTypeList` |
| Expressions and tuples | `.expressionList`, `.tupleTypeElementList`, `.tuplePatternElementList` |
| Closure signatures | `.closureParameterList`, `.closureShorthandParameterList`, `.closureCaptureList` |
| Enum associated values | `.enumCaseParameterList` |
| Accessors | `.accessorList` |
| Switch cases and patterns | `.switchCaseList`, `.switchCaseItemList` |

An expression list includes call arguments and tuple expressions. Each
element retains its source and trailing comma, when present. Use a token or
content slice for a nested edit that changes an element, because the layout
owns its separators.

`SourceNode.members` and `SourceNode.statements` expose direct children in
source order. A member's `property` projection returns a `Property` when the
member declares one binding. You can inspect its visibility, attributes and
other properties in your ordering logic. An attribute's `argument` projection
returns its single unlabelled expression, and
`hasAttribute("Environment", argument: \.isKeyPath)` checks that form directly.

You can set whitespace between adjacent list elements with a condition:

```swift
try Layout(block.statements) {
  BlankLine(
    between: { $0.kind == .variableDeclaration },
    and: { $0.call != nil }
  )
}
```

`between:and:` matches in either direction. `before:` checks the following
element and `after:` checks the preceding element. `Newline` takes the same
conditions. These forms keep every element in source order and preserve gaps
that do not match. Repeated requests for a gap combine, while conflicting
requests throw an error.

You can combine these conditions with groups in one `Layout`. Bylaws groups
and sorts the elements first, then checks the conditions against the resulting
adjacent pairs. Gaps outside the affected regions retain their original
whitespace.

A node's `call` projection recognises calls enclosed by `try`, `await` or
parentheses. A call inside a binding or nested body does not make the
outer node a call. Use `contains(.functionCall)` to include descendant calls.

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

Use the same selection and layout body in a test, then report the result:

```swift
import Bylaws
import Testing

@Test("Class attributes use alphabetical order")
func orderedAttributes() async throws {
  let app = Codebase(root: .automatic(), including: ["Sources/**"])
  let violations = try await app.classes.violations("Order attributes on one line") { declaration in
    let attributes = declaration.attributes
    try Layout(attributes) {
      Line(attributes.sorted { $0.name < $1.name })
    }
  }

  violations.report()
}
```

Run `bylaws lint --autocorrect` to apply corrections and run the rules again.
See <doc:CorrectingSource> for previewing edits and selecting rules or tests.

## Limits

A layout preserves captured source elements. You can combine `Layout` with
`Replace`, `Insert`, `Remove` or `Unwrap` in the same correction closure. See
<doc:CorrectingSource> for changes to names, literals and other content.
Layout checks reject foreign source, missing elements and unclear comment
ownership. Conditional-compilation boundaries and formatting-control comments
also stop rearrangement.
Each element must appear once in a layout builder. Conflicting captured
layouts and overlapping raw text replacements are rejected.
A child `Layout` or `Replace` can sit beside the containing `Layout` in the
correction closure. Bylaws combines compatible edits before applying the fix.

The CLI applies one set of corrections before verification. If a separate
layout joins lines and makes another call too long, verification reports the
remaining violation. Run `--autocorrect` again to apply that new correction.

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
to both rule forms.
