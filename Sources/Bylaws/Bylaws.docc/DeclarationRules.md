# Declaration rules

Check names, types, members, calls and declaration details.

## Overview

You can select declarations by name, path or another condition and check them
against your project's conventions. Use a parameterised test for one case per
declaration, or `violations(of:)` to report the failures together.

The examples use `Codebase.app` from <doc:GettingStarted> and the `Bylaws` and
`Testing` imports. <doc:CombiningChecks> shows how to combine these conditions
in a `Rule` and check members with key paths.

## Naming and inheritance

You can use `inherits(from:)` to check inheritance through typealiases and
intermediate base classes or `conforms(to:)` to check protocol conformance.
Both follow declarations included in the codebase. To check the inheritance
clause on the declaration itself, use `directlyInherits(from:)`:

```swift
@Test(
  "View models inherit from BaseViewModel",
  .annotatesViolations,
  arguments: try await Codebase.app.classes.suffixed("ViewModel")
    .excluding("BaseViewModel")
)
func inheritsBase(_ viewModel: Class) {
  #expect(viewModel.inherits(from: "BaseViewModel"))
}

@Test("Repository types are not classes")
func repositoriesAreNotClasses() async throws {
  let repositoryClasses = try await Codebase.app.classes.suffixed("Repository")
  #expect(repositoryClasses.isEmpty)
}
```

A name filter can accept several values and match any of them, or it can use a
regular expression:

```swift
@Test(
  "Screen types are final",
  .annotatesViolations,
  arguments: try await Codebase.app.classes
    .suffixed("ViewModel", "ViewController")
)
func isFinal(_ aClass: Class) {
  #expect(aClass.isFinal)
}

@Test("Feature flags follow the naming scheme")
func flagNames() async throws {
  let flags = try await Codebase.app.properties.prefixed("ff_")
  let wellNamed = try flags.nameMatching("ff_[a-z_]+")
  #expect(flags.count == wellNamed.count)
}
```

## Check every type kind

When a rule applies to classes, structs, enums and actors, query `types` to
check all four kinds together:

```swift
@Test(
  "Public types have documentation",
  .annotatesViolations,
  arguments: try await Codebase.app.types.where(\.isPublic)
)
func isDocumented(_ type: NominalType) {
  #expect(type.isDocumented)
}

@Test("Models are value types")
func modelsAreValueTypes() async throws {
  let models = try await Codebase.app.types.under("Sources/Models")
  #expect(models.violations(of: .isStruct || .isEnum).isEmpty)
}
```

To check a class's `final` modifier or an enum's cases, use `classes` or `enums`
instead of `types`.

## Restrict calls to one type

This parameterised test creates one case for every function that calls
`UserDefaults`, then permits those calls only in `PreferencesStore`:

```swift
@Test(
  "Functions that call UserDefaults belong to PreferencesStore",
  .annotatesViolations,
  arguments: try await Codebase.app.functions.where(.calls("UserDefaults"))
)
func userDefaultsIsContained(_ function: Function) {
  #expect(function.enclosingTypeName == "PreferencesStore")
}
```

Property queries include calls in initial values and accessors. For example,
`.calls("UserDefaults")` finds a property initialised with
`UserDefaults(suiteName: "app")`. Add this check alongside the function rule:

```swift
@Test(
  "Properties that call UserDefaults belong to PreferencesStore",
  .annotatesViolations,
  arguments: try await Codebase.app.properties
    .where(.calls("UserDefaults"))
)
func userDefaultsPropertyIsContained(_ property: Property) {
  #expect(property.enclosingTypeName == "PreferencesStore")
}
```

These checks match call names in the source. A later call such as
`defaults.bool(forKey:)` needs its own name check because Bylaws does not infer
the receiver's type.

You can use a dotted name to select a member call. For example,
`Task.detached` matches that member without matching `Task.sleep`:

```swift
@Test("Functions do not create detached tasks")
func noDetachedTasks() async throws {
  let violations = try await Codebase.app.functions
    .violations(matching: .calls("Task.detached"))
  #expect(violations.isEmpty)
}

@Test("Only the logging layer prints")
func printingIsContained() async throws {
  let violations = try await Codebase.app.functions
    .outside("Sources/Logging")
    .violations(matching: .calls("print", "NSLog", "debugPrint"))
  #expect(violations.isEmpty)
}
```

A call name can include argument labels when the rule applies to one form of an
API. Write `_` for an unlabelled argument and `()` for a call with no arguments:

```swift
@Test("Use ImageAsset instead of UIImage(named:)")
func bansUIImageNamed() async throws {
  let violations = try await Codebase.app.calls
    .violations(matching: .references("UIImage(named:)"))
  #expect(violations.isEmpty)
}
```

The labels must match in order, so this rule permits `UIImage(systemName:)`. A
trailing closure has no label of its own, so `Task.detached()` matches
`Task.detached { }`.

You can also check a call's arguments. This rule requires an argument in
each `fatalError` call:

```swift
@Test("fatalError calls include an argument")
func fatalErrorArguments() async throws {
  let callsWithoutArguments = try await Codebase.app.calls
    .named("fatalError")
    .where(\.arguments.isEmpty)
  #expect(callsWithoutArguments.isEmpty)
}
```

## Stored enum values

Renaming a case in a string-backed `Codable` enum changes its encoded value
unless the case declares an explicit raw value. You can require that value
for enums that declare both `String` and `Codable`:

```swift
@Test(
  "String-backed Codable enums declare explicit raw values",
  .annotatesViolations,
  arguments: try await Codebase.app.enums
    .where(.conforms(to: "Codable"))
    .where(.directlyInherits(from: "String"))
)
func codableEnumsDeclareRawValues(_ anEnum: Enum) {
  let implicit = anEnum.cases.filter { $0.rawValue == nil }
  #expect(implicit.isEmpty)
}
```

## File organisation

You can require one top-level type per file and a filename that matches its
type by using a shared helper to select top-level classes, structs, enums
and actors:

```swift
func topLevelTypeNames(in file: SourceFile) -> [String] {
  file.types.filter { $0.enclosingTypeName == nil }.map(\.name)
}

@Test(
  "Files declare at most one top-level type",
  .annotatesViolations,
  arguments: try await Codebase.app.files
)
func oneTypePerFile(_ file: SourceFile) {
  #expect(topLevelTypeNames(in: file).count <= 1)
}

@Test(
  "A file is named after the type it declares",
  .annotatesViolations,
  arguments: try await Codebase.app.files
)
func fileNameMatchesType(_ file: SourceFile) {
  guard let name = topLevelTypeNames(in: file).first else { return }
  #expect(file.name == "\(name).swift")
}
```

For required folders and declaration paths, see <doc:FolderRules>. To require
a related type, such as a test suite for each repository, see
<doc:CorrespondingTypes>.

## SwiftUI conventions

A `@State` property belongs to one view, so its access can remain private. This
rule combines the `View` conformance with the property attribute:

```swift
@Test(
  "View state stays private",
  .annotatesViolations,
  arguments: try await Codebase.app.structs.where(.conforms(to: "View"))
)
func viewStateIsPrivate(_ view: Struct) {
  let exposed = view.properties
    .filter { $0.hasAttribute("State") || $0.hasAttribute("StateObject") }
    .filter { $0.visibility > .private }
  #expect(exposed.isEmpty)
}
```

## Protocol requirements

You can require repository protocols to declare asynchronous functions and
reject service functions with a parameter labelled `completion`:

```swift
@Test(
  "Repository protocol functions are async",
  .annotatesViolations,
  arguments: try await Codebase.app.protocols.suffixed("Repository")
)
func repositoriesAreAsync(_ aProtocol: ProtocolDeclaration) {
  let blocking = aProtocol.requiredFunctions.filter { !$0.isAsync }
  #expect(blocking.isEmpty)
}

@Test("Service functions have no completion parameter")
func servicesHaveNoCompletionParameter() async throws {
  let callbacks = try await Codebase.app.functions
    .under("Sources/Services")
    .where(.hasParameter(labelled: "completion"))
  #expect(callbacks.isEmpty)
}
```

## Written types

You can inspect an explicit type annotation through
``/BylawsSemantics/TypeReference``. This rule rejects properties whose names
end in `ID` and whose annotations use `String`, `Int` or `UUID`:

```swift
@Test("Identifiers use domain types")
func identifiersAreDomainTypes() async throws {
  let violations = try await Codebase.app.properties
    .under("Sources/Domain")
    .suffixed("ID")
    .violations(matching: .hasType("String", "Int", "UUID"))
  #expect(violations.isEmpty)
}
```

You can limit optional properties when your models use enums to represent
alternative states. This example permits at most one property with a written
optional type per model:

```swift
@Test(
  "Models have at most one optional property",
  .annotatesViolations,
  arguments: try await Codebase.app.structs.under("Sources/Domain")
)
func modelsAvoidPairedOptionals(_ model: Struct) {
  let optionals = model.properties.filter { $0.type?.isOptional == true }
  #expect(optionals.count <= 1)
}
```

The `referencing:` matcher also checks generic arguments. This rule rejects
`ManagedObject` in a public function's parameter types, including a collection
such as `[ManagedObject]`:

```swift
@Test("The domain layer hides persistence types")
func domainHidesPersistence() async throws {
  let violations = try await Codebase.app.functions
    .under("Sources/Domain").where(.isPublic)
    .violations(matching: .hasParameter(referencing: "ManagedObject"))
  #expect(violations.isEmpty)
}
```

You can inspect an array or set's `elementType`, such as `Order` in an
`[Order]` annotation. A dictionary provides `keyType` and `valueType`, which
let you check its key type separately:

```swift
@Test(
  "A dictionary in the domain layer is keyed by a domain type",
  .annotatesViolations,
  arguments: try await Codebase.app.properties.under("Sources/Domain")
)
func dictionaryKeysAreDomainTypes(_ property: Property) {
  guard let key = property.type?.keyType else { return }
  #expect(!["String", "Int", "UUID"].contains(key.name))
}
```

Properties without a type annotation have a `nil` type, so check for a missing
annotation too if your rule must cover every property.

## Concurrency conventions

You can restrict annotations that bypass compiler checks. This rule reports
`nonisolated(unsafe)` properties and classes that declare `@unchecked Sendable`:

```swift
@Test("Sources declare no unsafe concurrency annotations")
func noUnsafeConcurrency() async throws {
  let unsafeProperties = try await Codebase.app.properties
    .violations(matching: .isNonisolatedUnsafe)
  #expect(unsafeProperties.isEmpty)

  let uncheckedTypes = try await Codebase.app.classes
    .violations(matching: .declaresInheritance("@unchecked Sendable"))
  #expect(uncheckedTypes.isEmpty)
}
```

You can also reject named blocking APIs in asynchronous functions or require
each function to contain an `await`:

```swift
@Test("Async functions do not call DispatchSemaphore or NSLock")
func noBlockingInAsyncCode() async throws {
  let blocking = try await Codebase.app.functions
    .where(.isAsync)
    .violations(matching: .calls("DispatchSemaphore", "NSLock"))
  #expect(blocking.isEmpty)
}

@Test("Async functions contain an await")
func asyncFunctionsAwait() async throws {
  let neverAwaits = try await Codebase.app.functions
    .where(.isAsync)
    .violations(of: \.awaitCount > 0)
  #expect(neverAwaits.isEmpty)
}
```

The second rule requires a written `await` even in functions that are
asynchronous only to satisfy a protocol. It checks syntax rather than whether
the function suspends at run time.

During a migration, you can also track `@preconcurrency` imports with
`imports.violations(matching: .hasAttribute("preconcurrency"))` and record
the existing violations in a baseline.

## Visibility and attributes

You can select declarations by attribute or property wrapper. This rule keeps
`@Published` properties in types whose names end in `ViewModel`:

```swift
@Test(
  "Published properties belong to view model types",
  .annotatesViolations,
  arguments: try await Codebase.app.properties
    .where(.hasAttribute("Published"))
)
func publishedLivesInViewModels(_ property: Property) {
  #expect(property.enclosingTypeName?.hasSuffix("ViewModel") == true)
}
```

A minimum visibility check includes every higher access level. For example,
`.hasVisibility(atLeast: .public)` also includes `open` declarations where
Swift permits them:

```swift
@Test("The public API of the domain layer is documented")
func publicDomainIsDocumented() async throws {
  let violations = try await Codebase.app.structs
    .under("Sources/Domain")
    .where(.hasVisibility(atLeast: .public))
    .violations(of: .hasDocumentation)
  #expect(violations.isEmpty)
}
```

## Modifiers

If your delegates must be weak to prevent retain cycles, you can check that
convention by property name:

```swift
@Test("Delegate properties are weak")
func delegatesAreWeak() async throws {
  let violations = try await Codebase.app.properties
    .suffixed("Delegate", "delegate")
    .violations(of: .isWeak)
  #expect(violations.isEmpty)
}
```

To require a `super` call in each lifecycle override, you can check its body
with a parameterised test:

```swift
@Test(
  "A lifecycle override calls super",
  .annotatesViolations,
  arguments: try await Codebase.app.functions
    .named("viewDidLoad", "viewWillAppear", "viewDidAppear")
    .where(.isOverride)
)
func lifecycleOverridesCallSuper(_ function: Function) {
  #expect(function.calls("super.\(function.name)"))
}
```

Other modifier checks include `.isLazy` on properties, `.isMutating` on
functions and `.isIndirect` on enums. These examples restrict dynamic
functions and convenience initialisers to particular paths:

```swift
@Test("Only the test support layer declares dynamic functions")
func dynamicIsContained() async throws {
  let violations = try await Codebase.app.functions
    .outside("Sources/TestSupport")
    .violations(matching: .isDynamic)
  #expect(violations.isEmpty)
}

@Test("Domain initialisers are designated")
func domainHasNoConvenienceInitializers() async throws {
  let violations = try await Codebase.app.initializers
    .under("Sources/Domain")
    .violations(matching: .isConvenience)
  #expect(violations.isEmpty)
}
```

## Generic parameters

If your convention puts constraints beside generic parameters, you can
check the generic parameter clause:

```swift
@Test(
  "A generic parameter declares a constraint",
  .annotatesViolations,
  arguments: try await Codebase.app.functions.where(.isPublic)
)
func genericsAreConstrained(_ function: Function) {
  let unconstrainedParameters = function.genericParameters.filter {
    $0.constraintName == nil
  }
  #expect(unconstrainedParameters.isEmpty)
}
```

A constraint written in a separate `where` clause does not satisfy this rule.

## Require documentation

You can require a documentation comment on public functions:

```swift
@Test(
  "Public API is documented",
  .annotatesViolations,
  arguments: try await Codebase.app.functions.where(.isPublic)
)
func publicFunctionIsDocumented(_ function: Function) {
  #expect(function.isDocumented)
}
```

You can also check that a function's documentation names every parameter in
declaration order:

```swift
@Test(
  "Documented public functions describe each parameter",
  .annotatesViolations,
  arguments: try await Codebase.app.functions
    .where(.isPublic && .hasDocumentation)
)
func documentsEachParameter(_ function: Function) {
  let parameterNames = function.parameters.map(\.name)
  #expect(function.documentedParameterNames == parameterNames)
}
```

## Limit size

You can set a file length limit with `lineCount`:

```swift
@Test(
  "Files contain at most 400 lines",
  .annotatesViolations,
  arguments: try await Codebase.app.files
)
func fileIsShort(_ file: SourceFile) {
  #expect(file.lineCount <= 400)
}
```

To limit a function's body length, you can compare `bodyLineCount` through a
key path:

```swift
@Test("Function bodies contain at most 60 lines")
func functionsAreShort() async throws {
  let violations = try await Codebase.app.functions
    .violations(of: \.bodyLineCount <= 60)
  #expect(violations.isEmpty)
}
```

For a diagnostic that names the property being checked, use a `Matcher` with
a written requirement as described in <doc:CombiningChecks>.

## Limit complexity

You can use `cyclomaticComplexity` to limit the branches in a function or
initialiser:

```swift
@Test("Functions stay within the complexity limit")
func functionsStayReadable() async throws {
  let violations = try await Codebase.app.functions
    .violations(of: \.cyclomaticComplexity <= 10)
  #expect(violations.isEmpty)
}
```

The count starts at zero and adds one for each `if`, `guard`, loop, `catch` and
`switch` case, including `if` and `switch` expressions and `for await` loops.
Each `fallthrough` subtracts one. Features such as `await`, typed throws, actor
isolation and macro invocations leave the count unchanged because they do not
introduce another path.

Closures contribute to the enclosing body's complexity, but local functions and
types do not. Code in every branch of an `#if` contributes to the source
model, as described in
<doc:WhatBylawsReads#Every-branch-of-an-if-is-read>.

For package boundaries and layer checks, see <doc:ArchitectureRules>. For
rules that need compiler or syntax data, see <doc:AdvancedRules>.
