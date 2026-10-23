# Formatting rule audit

This audit checks which Bylaws APIs an author can use to implement the rules
in SwiftFormat, swift-format and SwiftLint.

The inventories use released versions checked on 23 October 2026. Each guide
pins its source revision and lists every registered rule, including deprecated
entries. The swift-format guide also covers its configuration and pretty
printer, where much of that tool's formatting behaviour lives.

| Tool | Version | Inventory |
| --- | --- | --- |
| SwiftFormat | 0.64.1 | [169 entries](SwiftFormatRules.md), including eight deprecated rules |
| swift-format | 604.0.0 | [43 rules](SwiftFormatLanguageRules.md), plus configuration and pretty printer behaviour |
| SwiftLint | 0.65.1 | [256 rules and five aliases](SwiftLintRules.md) |

The routes describe the work a rule author must do. They do not establish
equivalence with every upstream option or test case. A diagnostic-only rule
can be useful without an automatic correction. A syntax transformation can
take more context than a local layout, even when both tools call it formatting.

## API changes

The audit led to shared source operations rather than a helper for each
upstream rule:

- `tokens` and `trivia` return captured edit targets with typed lexical kinds.
  An author can select operators, delimiters or comments without calculating
  byte ranges or matching text inside unrelated literals.
- `SourceNode.elements` exposes canonical syntax lists for conditions, generic
  clauses, inheritance, tuples, closure signatures, enum parameters, primary
  associated types, switch cases and accessors. The same layout builder
  arranges these lists.
- `SourceSlice.replacement(applying:)` combines separate edits within a
  containing slice, so a layout can include a correction with several changes.
- `SourceNode.contains(_:)` checks a node and its represented descendants.
  Source collections also support `only()` after filtering.
- Portable condition lists retain Swift's short-circuit behaviour and binding
  scope. The cookbook can use ordinary comma-separated conditions.

The individual inventories compare the original layout API with these changes
and retain the limits of each route.

## Examples and verification

The [correction cookbook](../../Sources/Bylaws/Bylaws.docc/CorrectingSourceCookbook.md)
starts with literal edits, then covers operators, comments, related files and
tests. The [formatting cookbook](../../Sources/Bylaws/Bylaws.docc/FormattingCookbook.md)
covers ordering, grouping, adjacent statements, width limits and nested layouts.
Each recipe includes a complete portable rule and a Swift Testing rule.

The documentation tests read the published code blocks. Both the portable
and native checks use inputs that need changes, compare corrected source with
exact expected text and check that a second run reports no violations or fixes.
A SwiftPM consumer compiles and runs the native examples and the documented
correction tests. Source API regressions cover inventory checks, comments,
Unicode, line endings and repeated layouts.

## Remaining limits

A captured layout preserves its input elements. Rules that add, remove or split
syntax use source replacements or native SwiftSyntax. Ambiguous comments and
conditional boundaries stop layout rearrangement. A rule can instead select
a smaller region with clear ownership.

Global line breaking, comment reflow, configurable tab widths and exact
formatter-specific indentation policies remain author work. Token access
removes range handling, but precedence, binding analysis and whole-program
behaviour can need more information. The compiler index supplies symbol data
for selected builds and is not a replacement for SwiftLint's SourceKit
analyser responses.

A successful correction check establishes source ownership and parseable
output. The rule author remains responsible for changes to program behaviour,
including declaration order, evaluation order and symbol references.
