# ``Bylaws``

Write architectural rules and run them with Swift Testing or the CLI.

## Overview

You can use Bylaws to check which modules may depend on one another, where a
type belongs or which code may call an API. For example, this test checks that
functions which call `UserDefaults` belong to `PreferencesStore`:

```swift
import Bylaws
import Testing

extension Codebase {
  nonisolated static let app = Codebase(
    root: .automatic(),
    including: ["Sources/**"]
  )
}

@Suite(.codebase(.app))
struct PersistenceBoundaryRules {
  @Test(
    "Functions that call UserDefaults belong to PreferencesStore",
    .annotatesViolations,
    arguments: try await Codebase.app.functions
      .where(.calls("UserDefaults"))
  )
  func userDefaultsIsContained(_ function: Function) {
    #expect(function.enclosingTypeName == "PreferencesStore")
  }
}
```

Start with <doc:GettingStarted>, then use <doc:RuleCookbook> to find a rule you
can adapt. <doc:RuleAdoption> covers advisory rules and baselines for a
codebase that has existing violations.

To run rules from a `Bylaws.swift` file, follow <doc:RunningRulesFromTheCLI>.

## Topics

### Start here

- <doc:GettingStarted>
- <doc:RuleCookbook>
- <doc:RuleAdoption>
- <doc:RunningRulesFromTheCLI>
- <doc:RunningRulesDuringBuilds>
- <doc:RunningRulesWithBazel>
- <doc:InspectingRules>

### Find a rule

- <doc:DeclarationRules>
- <doc:FolderRules>
- <doc:CorrespondingTypes>
- <doc:ArchitectureRules>
- <doc:DependencyRules>
- <doc:BazelDependencies>
- <doc:CombiningChecks>
- <doc:AdvancedRules>

### Understand the model

- <doc:WhatBylawsReads>
- ``/BylawsCore/Codebase``
- ``/BylawsCore/Glob``

### Querying

- ``/BylawsCore/Selection``
- ``/BylawsCore/Matcher``
- ``/BylawsCore/Violations``

### Rule traits

- ``CodebaseTrait``
- ``AnnotatesViolationsTrait``
- ``BaselineTrait``
- ``BaselineMode``

### Layering

- ``/BylawsCore/Layering``
- ``/BylawsCore/Layer``
- ``/BylawsCore/LayeringCheck``
- ``/BylawsCore/LayeringError``

### Package dependencies

- ``/BylawsSemantics/PackageManifest``
- ``/BylawsCore/PackageDependencyCheck``
- ``/BylawsCore/ImportGraph``
- ``/BylawsCore/BazelGraph``
- ``/BylawsCore/DependencyStabilityCheck``

### Baselines

- ``/BylawsCore/Baseline``

### The declaration model

- ``/BylawsSemantics/SourceFile``
- ``/BylawsSemantics/Class``
- ``/BylawsSemantics/Actor``
- ``/BylawsSemantics/Struct``
- ``/BylawsSemantics/Enum``
- ``/BylawsSemantics/NominalType``
- ``/BylawsSemantics/NominalTypeDeclaration``
- ``/BylawsSemantics/NominalTypeStorage``
- ``/BylawsSemantics/EnumCase``
- ``/BylawsSemantics/ProtocolDeclaration``
- ``/BylawsSemantics/Extension``
- ``/BylawsSemantics/Function``
- ``/BylawsSemantics/Initializer``
- ``/BylawsSemantics/Property``
- ``/BylawsSemantics/Parameter``
- ``/BylawsSemantics/TypeReference``
- ``/BylawsSemantics/GenericParameter``
- ``/BylawsSemantics/Typealias``
- ``/BylawsSemantics/Import``
- ``/BylawsSemantics/ImportKind``
- ``/BylawsSemantics/FunctionCall``
- ``/BylawsSemantics/Attribute``
- ``/BylawsSemantics/Ownership``
- ``/BylawsSemantics/DeclarationLocation``
- ``/BylawsSemantics/Visibility``
