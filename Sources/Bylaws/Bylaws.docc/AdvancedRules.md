# Advanced rules

Use compiler data or source syntax for checks outside the declaration model.

## Overview

If a declaration query cannot answer your question, you can inspect the source
text or select the statements and expressions that matter to the rule. Use
`BylawsIndex` when the check needs a reference or conformance resolved by the
compiler.

The Swift Testing examples use `Codebase.app` from <doc:GettingStarted>.

## Use compiler data

To check conformances across modules, build those modules and add the
`BylawsIndex` product to your test target. The CLI includes index support, so
you can also run these rules with `bylaws lint` after a build.

This rule checks that types which conform to `UserRepository` belong to `Data`:

```swift
import Bylaws
import BylawsIndex
import BylawsIndexStore
import Testing

@Test("Repository conformers belong to the data layer")
func conformersStayInTheirLayer() async throws {
  let conformers = try await Codebase.app.conformers(
    of: "UserRepository",
    modules: ["Domain", "Data", "Feature"]
  )
  let outsideDataLayer = conformers.filter { $0.module != "Data" }
  #expect(outsideDataLayer.isEmpty)
}
```

Set `modules:` to the modules you want to check, including any that add
conformances through typealiases, refined protocols or extensions.

You can also find references to a symbol in the selected modules:

```swift
@Test("Only the networking layer uses the session type")
func sessionStaysContained() async throws {
  let users = try await Codebase.app.references(
    to: "URLSession",
    modules: ["Domain", "Data", "Networking"]
  )
  let outside = users.filter { $0.module != "Networking" }
  #expect(outside.isEmpty)
}
```

`.calls("URLSession")` matches the written name, so it misses a call through a
typealias and can match a different type with the same name. The reference query
uses the symbol identities recorded by the compiler.

You can require selected declarations to have references in the modules you
check. For example, this rule checks for uses of the named types within
`Domain`:

```swift
@Test(
  "Domain types have references within Domain",
  arguments: ["OrderMapper", "OrderStore", "OrderFormatter"]
)
func domainTypesHaveReferences(_ name: String) async throws {
  let index = try await Codebase.app.projectIndex(modules: ["Domain"])
  #expect(!index.definitions(of: name).isEmpty)
  #expect(!index.references(to: name).isEmpty)
}
```

This check covers only the selected build and modules, so check for callers in
other packages before removing a declaration. Calls through a protocol
requirement also need a separate check because the index records them under
the requirement rather than the implementation.

SwiftPM debug builds write index data by default. For release builds, pass
`--enable-index-store`. If Bylaws cannot find the index store, set
`BYLAWS_INDEX_STORE` to its path.

Use an index store for the build configuration you want to check. If the store
contains several configurations, select the relevant units with
`unitOutputFiles:`.

## Look up a source position

You can look up the compiler occurrences at an exact source location. This
test helper checks that an identifier refers to a known definition:

```swift
func checkReference(
  at location: DeclarationLocation, to definition: IndexReference
) async throws {
  let index = try await Codebase.app.projectIndex(modules: ["Networking"])
  let references = index.occurrences(at: location).filter {
    $0.roles.contains(.reference) && !$0.roles.contains(.implicit)
  }
  #expect(references.count == 1)
  #expect(references.first?.symbol.usr == definition.symbol.usr)
}
```

Pass a definition from the index and the location of the identifier you want
to check. For `client.send()`, use the position of `send` to look up the
method. The lookup takes the file path, line and UTF-8 byte column from the
source used in the indexed build.

The helper compares `symbol.usr` to check that the reference and definition
refer to the same symbol, even when other declarations have the same name.
It also checks the number of results because a position can have several
indexed occurrences or none. For example, the compiler can omit a local
value from the index.

You can also use `index.occurrences(at:)` in a CLI rule body, then filter the
results as shown above. The CLI runs index queries in an asynchronous context,
so keep the query outside a synchronous matcher or collection closure.
For direct access through `BylawsIndexStore`, use
`index.occurrences(in:line:column:)`.

## Source-text checks

You can read `sourceText` on a file or declaration when a rule needs the exact
text. This example requires a copyright comment at the start of each file:

```swift
@Test(
  "Files start with a copyright comment",
  arguments: try await Codebase.app.files
)
func hasCopyrightComment(_ file: SourceFile) {
  #expect(
    file.sourceText.hasPrefix("// Copyright"),
    sourceLocation: file.testingLocation
  )
}
```

A text search treats comments, string literals and identifiers alike. To find a
word such as `TODO` only in comments, inspect SwiftSyntax trivia as shown below.

## Check syntax patterns

Use `syntaxNodes(of:_:)` to select specific statements, expressions and
declarations. Each `SourceNode` gives you its source text and location, along
with its children, descendants, parent and ancestors. For a call node, you can
also use the same `FunctionCall` API as `Codebase.calls`.

For example, a project that uses `NSLock.withLock` can report a manual unlock
inside `defer`:

```swift
let deferredUnlock = Matcher<SourceNode>("call unlock from defer") { node in
  node.call?.references("lock.unlock") == true
    && node.ancestors.contains { $0.kind == .deferStatement }
}

Rule("scoped-locking", "Locks use withLock") {
  try await Codebase.app.syntaxNodes(of: .functionCall)
    .violations(matching: deferredUnlock)
}
```

You can select several kinds in one query:

```swift
let nodes = try await Codebase.app.syntaxNodes(
  of: .functionCall,
  .awaitExpression,
  .deferStatement
)
```

These rules work in compiled tests and the CLI.

## Use SwiftSyntax directly

When a check needs more detail, `withSyntax` gives you access to the full
SwiftSyntax tree, including its tokens and trivia.

A `default` case can hide a new enum case from the compiler's exhaustiveness
check. If your domain switches must name every case, you can enforce that
convention with a custom visitor in a Swift Testing target:

```swift
import SwiftSyntax

@Test(
  "Switches name every case rather than using default",
  arguments: try await Codebase.app.files.under("Sources/Domain")
)
func switchesAreExhaustive(_ file: SourceFile) {
  let usesDefault = file.withSyntax { tree in
    DefaultCaseFinder(viewMode: .sourceAccurate).finds(in: tree)
  }
  #expect(!usesDefault, sourceLocation: file.testingLocation)
}

private final class DefaultCaseFinder: SyntaxVisitor {
  private var found = false

  func finds(in tree: SourceFileSyntax) -> Bool {
    found = false
    walk(tree)
    return found
  }

  override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
    found = found || node.label.is(SwitchDefaultLabelSyntax.self)
    return .visitChildren
  }
}
```

You can also start at a declaration instead of the whole file. This form returns
`nil` when the declaration's position contains no node of the requested type:

```swift
let memberCount = file.withSyntax(of: viewModel, as: ClassDeclSyntax.self) {
  $0.memberBlock.members.count
}
```

SwiftSyntax stores comments as trivia attached to tokens. You can read that
trivia through `withSyntax` to find a `TODO` marker in a comment:

```swift
@Test(
  "Domain comments contain no TODO markers",
  arguments: try await Codebase.app.files.under("Sources/Domain")
)
func hasNoTODO(_ file: SourceFile) {
  let comments = file.withSyntax { tree in
    Trivia(pieces: tree.tokens(viewMode: .sourceAccurate).flatMap {
      ($0.leadingTrivia + $0.trailingTrivia).filter(\.isComment)
    }).description
  }
  #expect(!comments.contains("TODO"), sourceLocation: file.testingLocation)
}
```

The class-member and comment checks above use SwiftSyntax APIs supported by the
CLI, so you can run them from the CLI or as compiled tests. If a rule defines a
custom `SyntaxVisitor`, run it as a compiled Swift test.

See <doc:RunningRulesFromTheCLI> for CLI setup and its supported APIs.
