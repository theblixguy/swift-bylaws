# Check Bazel target dependencies

Use Bazel's configured dependency graph to check relationships between targets.

## Export the graph

Generate the export with Bazel 8 or later, because earlier versions can omit
configuration data for dependencies.

You can check Bazel targets and their dependencies without a `Package.swift`.
Start by exporting the graph for your app, then run the rules after the export
succeeds:

```sh
bazel cquery 'deps(//app:app)' \
  --output=jsonproto \
  --transitions=lite \
  --proto:include_configurations > bazel-graph.json &&
  bazel run @swift-bylaws//:bylaws -- lint
```

Replace `//app:app` with your app's target label and pass the same build options
you use for that app. For example, add `--config=ios` if your project uses that
configuration. `cquery` analyses the targets without compiling the app.

Keep the export step in your local check command or CI script so the rules use
current dependencies. The generated JSON file belongs in your build outputs,
not version control. Bylaws reads the file when the rule runs and leaves Bazel
execution to your script.

## Keep feature targets independent of a database

You can use Bazel tags to identify feature targets regardless of where their
files live. Add `tags = ["feature"]` to those targets, then put this rule in
`Bylaws.swift` at the workspace root:

```swift
import Bylaws

let codebase = Codebase()

let projectRules: [Rule] = [
  Rule("feature-dependencies", "Features independent of database") {
    let graph = try await codebase.bazelGraph(from: "bazel-graph.json")
    let features = graph.targets.filter { $0.tags.contains("feature") }
    let offenders = features.filter { feature in
      graph.transitiveTargetDependencies(of: feature).contains {
        $0.label == "//storage:Database"
      }
    }
    return Violations(
      rule: "avoid database dependencies",
      offenders: offenders,
      checkedCount: features.count
    )
  },
]
```

This checks both direct dependencies and dependencies through other targets.
For example, a feature that depends on a repository target which depends on
`//storage:Database` fails the rule. The violation points to the feature's
declaration in its `BUILD` file.

To check immediate dependencies instead, use
`graph.directTargetDependencies(of: feature)`.

You can run the same rule array from Swift Testing after generating the export:

```swift
import Testing

@Test("Architecture rules", arguments: projectRules)
func architecture(rule: Rule) async throws {
  try await rule.report()
}
```

## Choose the targets and configuration to check

The graph covers the targets returned by your query, including their file and
tool dependencies. Use `deps(...)` to include every dependency of the app, or
`deps(set(//app:app //extension:extension))` to check several entry targets.
Bylaws rejects an export when a dependency refers to a target missing from it.

Each target has a `label`, `ruleClass`, `tags` and `configuration`. The
configuration contains Bazel's checksum, tool status and exported build options.
Unconfigured targets such as source files have a `nil` configuration, and files
and package groups have no `ruleClass`.

Bazel can use the same target in several configurations within one build.
Bylaws keeps those targets separate and follows the dependency for the
corresponding configuration, including the branch selected by `select()`.
This also covers split transitions, where one target depends on several
configurations of another target. To check another platform or set of build
options, generate a new export with those options and run the rules again.

You can check dependencies added by aspects and the toolchains selected for the
build through the same dependency methods. Bazel includes these relationships
in the export when implicit dependencies, tool dependencies and aspects are
enabled, which is the default.

## Check build settings

You can use `configuration.isTool` to select build tools separately from app
targets. For example, this selects tools built without optimisation:

```swift
let coreOptions = "com.google.devtools.build.lib.analysis.config.CoreOptions"
let offenders = graph.targets.filter { target in
  guard let configuration = target.configuration else { return false }
  return configuration.isTool
    && configuration.buildOptions[coreOptions]?["compilation_mode"] != "opt"
}
```

`buildOptions` keeps the option groups and string values from Bazel's export.
Native options use their full option class names, while user-defined settings
are in the `user-defined` group. For example, you can read a custom setting with
`configuration.buildOptions["user-defined"]?["//settings:api"]`.

The exported groups depend on the Bazel version and the target's configuration.
An absent option returns `nil`, so a rule can report it as a violation or skip
that check. Use `configuration.checksum` when you need the configuration's
identifier.

## Export requirements

Keep the flags in the export command above and include implicit and tool
dependencies. A plain `bazel query` result or an export without configured edges
cannot describe the selected build's dependencies.

If Bazel omits a target's source position, Bylaws reports its violations at the
export file instead. Paths passed to `bazelGraph(from:)` are relative to the
codebase root unless you supply an absolute path.

An empty query produces an empty graph. If your rule must check at least one
target, check the selected target count as part of the rule.
