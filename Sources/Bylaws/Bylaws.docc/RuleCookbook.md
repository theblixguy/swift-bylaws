# Rule cookbook

Find a rule for your project's conventions, folder layout or dependencies.

## Overview

You can use Bylaws to keep view models in their feature folders, prevent a
domain layer from using UI code or require a test type for each repository.
Choose a guide below for examples you can adapt to your project's paths, names
and conditions.

## Find an example

| What you want to check | Guide |
| --- | --- |
| Naming, inheritance, protocol requirements, SwiftUI state or lifecycle calls | <doc:DeclarationRules> |
| Feature folders and the types or files permitted inside them | <doc:FolderRules> |
| A test suite for each repository or a view model for each view | <doc:CorrespondingTypes> |
| Imports between layers and dependencies declared in a package | <doc:ArchitectureRules> |
| References between files and cycles between named file groups | <doc:DependencyRules> |
| Several conditions or the members of a declaration | <doc:CombiningChecks> |
| Literal values, interpolation arguments and member references | <doc:InspectingExpressions> |
| Code permitted only inside a particular `#if` branch | <doc:ConditionalCompilation> |
| Logging, keychain access, authentication code and security settings | <doc:SecurityCookbook> |
| Compiler-resolved symbols, source text or other Swift syntax | <doc:AdvancedRules> |

## Set up and run a recipe

<doc:GettingStarted> covers installation and defines the `Codebase.app` value
used by the Swift Testing examples. Those examples use `import Bylaws` and
`import Testing`. Add the `BylawsIndex` product and imports where a guide uses
compiler data.

You can run a complete `Bylaws.swift` example through the CLI or as Swift tests,
then add individual `Rule` examples to its `[Rule]` array.
<doc:RunningRulesFromTheCLI> covers CLI setup and the Swift features you can use
in portable rules.

The CLI can check your Swift files without building the project first. Rules
that use the compiler index need data from a build of the code they check.
<doc:WhatBylawsReads> explains the information available to each kind of rule.

## Check the rule before you enforce it

Try the rule against code that should pass and code that should fail.
<doc:RuleAdoption> shows how to test a rule with source strings and introduce
it as an advisory or with a baseline for existing violations.

If a rule passes when you expect a violation, use <doc:InspectingRules> to see
which declarations its queries select and exclude.
