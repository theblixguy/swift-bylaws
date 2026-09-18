# Frequently asked questions

If you're setting up Bylaws for the first time, start with the
[README](README.md#get-started).

## How is this different from SwiftLint?

SwiftLint primarily checks style and correctness, including naming and
whitespace. Bylaws lets you check decisions that apply across your project, such
as which modules may import one another or which base class a screen model must
inherit. If you want, you can run both tools in the same project!

## Why are rules Swift code instead of a configuration file?

Swift lets you express project-specific checks in the same language you use for
your app. For example, you might require every function in a service protocol to
be asynchronous, except those with a particular attribute. You can write that
condition in Swift and extract it into a function for other rules to use. A
configuration-based system would need its own syntax for those conditions and
reusable checks.

You can also share rules through a Swift package and test them against small
code examples. When the rules belong to a test target, you also get compiler
type checks and editor support for completion and refactoring.

You can run the same rules from the command line if they use the CLI's
[supported Swift subset].

## Can rules enforce MVVM, MVP or another architecture?

Yes. You can choose the dependencies and type requirements you want to enforce,
then write a rule for each one. For example:

| Architecture       | Rules you can write                                                                                                      |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| MVVM               | Keep UIKit and SwiftUI imports out of the model layer. Require screen models to conform to an application protocol.      |
| MVP                | Require presenters to conform to a presenter protocol. Keep view implementation dependencies out of the presenter layer. |
| Clean Architecture | Allow a feature module to import domain interfaces while keeping persistence implementation imports in the data layer.   |

Use import rules when layers are separate modules. If layers are folders inside
one module, use compiler-index references to check dependencies between their
types. The [README examples](README.md#practical-rules) show how to check base
classes and protocol conformances. For dependencies between modules or folders,
see [Architecture rules].

These rules check the code's structure, not behaviour. If a presenter must refer
to a view protocol, Bylaws can check that requirement, but you need a regular
unit or UI test to check that the presenter updates the view correctly.

## Can we require a folder layout for every feature?

Yes, you can use `checkFolderLayout(matching:containing:)` to require `Models`,
`ViewModels` and `Views` inside every folder that matches `Sources/App/*`. The
`*` matches any feature name, so the rule also checks any features you add
later.

You can then select view models by name or conformance and use
`violations(outsidePaths:)` to require them under `Sources/App/*/ViewModels/**`.
Both checks run before a build. The [folder guide] shows the complete rules and
an example with shared folders for the whole module.

## Which platforms does it run on?

Bylaws supports macOS 14, iOS 13 and Linux with Swift 6.2 or later. Windows is
currently unsupported.

The CLI and language server are available as universal binaries for Apple
Silicon and Intel Macs and as x86-64 Linux binaries with glibc 2.35 or later.

## Does it work with an Xcode project rather than a package?

Yes. You can keep `Bylaws.swift` at the project root and run `bylaws lint`
across the app and its local packages. Rules don't need a root `Package.swift`
or Bylaws dependency in those packages.

If you prefer tests, add the `Bylaws` product to the app's test target and
select the source folders that the rules should check. The [Xcode setup guide]
shows the configuration for it.

## Can Bylaws run during a build?

Yes. Attach `BylawsBuildToolPlugin` to any one of your SwiftPM targets included
in the build, then run:

```sh
swift build --disable-build-manifest-caching
```

Without the flag, SwiftPM can reuse a build plan and skip checks after a source
edit. The plugin runs the package's rules before compilation and applies any
recorded baselines.

Compiler-index queries need a completed build, so run those rules separately
after the build. Advisory violations let the build pass, but SwiftPM hides their
warning text. To see those warnings, run:

```sh
swift package --allow-writing-to-package-directory bylaws
```

[Build-tool plugin setup] explains how to add the plugin and use shared rule
packages. You can attach the plugin to SwiftPM targets, but not directly to an
Xcode project target.

## Why does the plugin need `--allow-writing-to-package-directory`?

The command plugin needs permission to save a baseline beside your rules when
you ask it to record violations. The flag grants that permission for the run.

## We have hundreds of violations today. How do we adopt a rule?

Use an advisory rule when you want to see violations without failing the run. If
you want to reject new violations while keeping the existing ones, record a
baseline from the project root:

```sh
bylaws lint --record-baseline Bylaws.baseline.swift
bylaws lint
```

Review and commit the generated baseline with the rule. Bylaws reports new
violations and tells you when a violation recorded in the baseline is no longer
present. After you fix a recorded violation, review the change and record the
baseline again to remove its entry.

You can use the same baseline with the CLI and `Rule.report()`. For advisory
test suites and baselines for declaration assertions, see
[Adopting rules].

## Can we share rules between projects?

Yes. Put the shared rules in a Swift package with a public function returning
`[Rule]`, then import its module in each project's rules file. Both SwiftPM
plugins support these imports and you can compile the same file in a test
target. For setup, see
[Share rules through SwiftPM].

## Why doesn't Bylaws resolve types or expand macros?

Bylaws checks your source files before compilation, when inferred types and
macro-generated declarations are unavailable. You can check a written type
annotation such as `: String` or the use of a macro such as `@Observable`, but
inferring `String` from `let title = "Checkout"` needs the compiler.

For resolved references and conformances across modules, you can use
`BylawsIndex` after a build.
[What Bylaws reads] explains which information is available through the
compiler's index.

## Can I check code inside `#if` blocks?

Yes. Bylaws checks the code inside every branch, including branches for other
platforms. For example, when you run a rule on a Mac, it can check code inside
both `#if os(iOS)` and `#if os(macOS)`. Rules that use the compiler's index are
limited to the code included in the build, so an index from a macOS build
contains the macOS branch but not the iOS branch.

## Why does the CLI reject a file the Swift compiler accepts?

The CLI interprets a supported subset of Swift without compiling your rules. If
a rule uses an unsupported language feature or API, the CLI reports a load error
and stops the run. You can run that rule in a test target to use the full Swift
language.

[Running rules from the CLI] lists the supported types, properties and methods.

## Is it fast enough for a large repository?

In the [benchmarks](README.md#benchmarks), `bylaws lint` checked ten rules
across 3,013 Firefox iOS files in 0.53 seconds. The time depends on your rules
and project, so measure a run with your own code before adding it to a build or
CI.

## Can a rule fix the code it flags?

Bylaws reports a violation and its source location so you can decide how to fix
it. For example, a disallowed import might call for moving a type to another
layer or passing a dependency through a protocol, which is a design choice that
you have to make yourself.

## Where can I ask for help?

Open a [GitHub issue](https://github.com/theblixguy/swift-bylaws/issues) for a
bug, setup question or proposed rule. Include the Swift version, the command you
ran and a reproducer for the rules you used.

[Share rules through SwiftPM]:
  https://theblixguy.github.io/swift-bylaws/documentation/bylaws/runningrulesfromthecli#Share-rules-through-SwiftPM
[supported Swift subset]:
  https://theblixguy.github.io/swift-bylaws/documentation/bylaws/runningrulesfromthecli#Supported-API
[Architecture rules]:
  https://theblixguy.github.io/swift-bylaws/documentation/bylaws/architecturerules
[folder guide]:
  https://theblixguy.github.io/swift-bylaws/documentation/bylaws/folderrules
[Xcode setup guide]:
  https://theblixguy.github.io/swift-bylaws/documentation/bylaws/gettingstarted#Set-up-an-Xcode-project
[Build-tool plugin setup]:
  https://theblixguy.github.io/swift-bylaws/documentation/bylaws/runningrulesduringbuilds
[Adopting rules]:
  https://theblixguy.github.io/swift-bylaws/documentation/bylaws/ruleadoption
[What Bylaws reads]:
  https://theblixguy.github.io/swift-bylaws/documentation/bylaws/whatbylawsreads
[Running rules from the CLI]:
  https://theblixguy.github.io/swift-bylaws/documentation/bylaws/runningrulesfromthecli
