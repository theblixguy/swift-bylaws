# Architecture rules

Check layer boundaries and Swift package dependencies.

## Overview

You can define which layers may depend on one another and check their source
imports against that rule. For a Swift package, you can also compare the
imports with the dependencies declared in `Package.swift`.

For permissions between individual files or cycles between named file groups,
see <doc:DependencyRules>. Those checks also work within one module.

The test examples use `Codebase.app` from <doc:GettingStarted> with
`import Bylaws` and `import Testing`. For a CLI rules file, declare
`let app = Codebase(including: ["Sources/**"])`, use `app` in place of
`Codebase.app` and put the rules in a `[Rule]` array.

## Layering and imports

Declare each layer and list the other layers that it can import. Bylaws then
reports any import between those layers that the list does not permit:

```swift
let appLayers = Layering(
  Layer("Domain", files: ["Sources/Domain/**"]),
  Layer(
    "Persistence",
    files: ["Sources/Persistence/**"],
    mayImport: ["Domain"]
  ),
  Layer("Checkout", files: ["Sources/Checkout/**"], mayImport: ["Domain"])
)

let projectRules: [Rule] = [
  Rule("module-boundaries", "Modules follow their declared dependencies") {
    try await Codebase.app.checkLayering(appLayers)
  },
]
```

If `CheckoutViewModel.swift` imports `Persistence`, the failure points to that
import. Bylaws also warns if a layer's patterns match no files, so you can check
whether the paths are correct.

Run these rules with the CLI or a Swift Testing test:

```swift
@Test(
  "Modules follow their declared dependencies",
  arguments: projectRules
)
func moduleDependencies(_ rule: Rule) async throws {
  try await rule.report()
}
```

You can use `mustImport` to require at least one file in a layer to import a
dependency:

```swift
Layer(
  "Checkout",
  files: ["Sources/Checkout/**"],
  mayImport: ["Domain"],
  mustImport: ["DesignSystem"]
)
```

If you want to forbid one dependency while permitting other imports, use `.any`
with `mustNotImport`:

```swift
Layer(
  "Feature",
  files: ["Sources/Feature/**"],
  mayImport: .any,
  mustNotImport: ["Persistence"]
)
```

The permitted dependencies must contain no cycles. For example, a layering
that lets `Domain` import `Data` and `Data` import `Domain` produces
``/BylawsCore/LayeringError/circularLayers(path:)``.

The layering permits imports from modules outside its list, such as Foundation
or a third-party package. You can restrict those imports with a separate rule:

```swift
@Test("The domain layer stays independent of UI frameworks")
func domainIsUIFree() async throws {
  let violations = try await Codebase.app.files.under("Sources/Domain")
    .violations(matching: .imports("UIKit", "SwiftUI"))
  #expect(violations.isEmpty)
}
```

You can also check an import's access level, attributes and kind. This rule
rejects `@testable` imports from the selected production source:

```swift
@Test("Production code has no @testable imports")
func noTestableImports() async throws {
  let violations = try await Codebase.app.imports
    .violations(matching: .hasAttribute("testable"))
  #expect(violations.isEmpty)
}
```

## Layers inside one module

You can check boundaries between folders in one module with `BylawsIndex`.
The rule uses compiler-resolved references to find a dependency between two
files, even though neither file imports the other:

```swift
import Bylaws
import BylawsIndex

let app = Codebase(root: .automatic(), including: ["Sources/**"])
let appLayers = Layering(
  Layer("Domain", files: ["Sources/App/Domain/**"]),
  Layer(
    "Persistence",
    files: ["Sources/App/Persistence/**"],
    mayImport: ["Domain"]
  ),
  Layer("Checkout", files: ["Sources/App/Checkout/**"], mayImport: ["Domain"])
)

let projectRules: [Rule] = [
  Rule("feature-boundaries", "Folders follow their declared dependencies") {
    try await app.indexedFindings(
      of: appLayers,
      modules: ["App"]
    )
  },
]
```

This version catches a reference from `CheckoutViewModel` to a type declared in
the Persistence folder even though both files belong to the `App` module.

Set `modules:` to the modules you want to check and build them before running
the rule from the CLI or a test target. SwiftPM debug builds write index data
by default, but a release build needs `--enable-index-store`.

The check covers explicit references whose use and definition are in the
selected source and the same module. It excludes compiler-generated implicit
references and skips a symbol if its definitions span several declared layers.

## Package dependencies

SwiftPM lets a file import a module that its target has not declared when
another dependency supplies that module. If the intermediate target later
removes its dependency, the first target stops compiling even though its source
has not changed. Compare the manifest with the imports in each target to catch
this problem:

```swift
Rule("package-dependencies", "Package.swift matches source imports") {
  try await Codebase.app.checkPackageDependencies()
}
```

An import from an undeclared package target is a violation, and a declared
dependency that no file imports also produces a failure. The check covers only
targets declared in `Package.swift`, because Bylaws cannot determine which
modules an external package supplies.

To check every target, include both `Sources` and `Tests` in the codebase.
You get a warning when a target has no files in that selection or Bylaws cannot
determine a value in `Package.swift`.

## Package manifest rules

You can query ``/BylawsCore/Codebase/packageManifest`` to check a package's
products, targets, dependencies, deployment platforms, traits, resources,
plugins and build settings.

For example, this rule requires each regular or executable target to have a
test target that depends on it:

```swift
@Test("Regular and executable targets have a dependent test target")
func targetsHaveTests() async throws {
  let manifest = try await Codebase.app.packageManifest
  let targets = try #require(
    manifest.targets().values
  )

  for target in targets where
    target.kind == .regular || target.kind == .executable
  {
    let testTargets = try #require(
      manifest.testTargets(dependingOn: target).values
    )
    #expect(!testTargets.isEmpty, "\(target.name) has no test target")
  }
}
```

The test target can have any name as long as it depends on the target being
checked.

If you want to include dependencies with platform or trait conditions, pass
`includingConditionalDependencies: true`. You can inspect those relationships
through `conditionalValues`.

You can reject unsafe flags across Swift, C, C++ and linker settings in one
rule:

```swift
@Test("Targets do not use unsafe build flags")
func targetsAvoidUnsafeFlags() async throws {
  let manifest = try await Codebase.app.packageManifest
  let targets = try #require(manifest.targets.values)

  for target in targets {
    let settings = try #require(target.buildSettings.values)
    #expect(!settings.contains { $0.usesUnsafeFlags })
  }
}
```

A `Package.swift` file can compute values that Bylaws cannot determine without
executing it. In that case, ``/BylawsSemantics/ManifestList/values`` is `nil`.
Use `#require` on `values` before asserting that something is absent, as the
example does. `knownValues` lets you inspect the unconditional values that
Bylaws could read, but that list may be incomplete.

## Dependency stability

You can use ``/BylawsCore/ImportGraph`` to see which targets depend on one
another and check their instability: outgoing dependencies divided by the total
number of incoming and outgoing dependencies. A value near 0 means most of a
target's dependencies point towards it, while a value near 1 means most point
towards other targets.

```swift
@Test("The domain target stays stable")
func domainIsStable() async throws {
  let graph = try await Codebase.app.importGraph()
  try #require(graph.isComplete)
  let domain = try #require(graph.targets.first { $0.name == "Domain" })
  #expect(domain.instability < 0.2)
}
```

To enforce the stable dependencies principle, use `checkDependencyStability()`
to require each dependency to point towards a target with equal or lower
instability:

```swift
Rule("stable-dependencies", "Dependencies point towards stability") {
  try await Codebase.app.checkDependencyStability()
}
```

Each violation names both targets and their instability values, with a source
location for the first import that creates the dependency.

`ignoring:` removes a target and all of its incoming and outgoing dependencies
from the graph.

For naming, type and declaration checks, see <doc:DeclarationRules>.
