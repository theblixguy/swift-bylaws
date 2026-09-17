# Running rules with Bazel

Check architectural rules as part of a Bazel build and reuse successful results.

## Overview

Add a `bylaws_lint` target to run rules during `bazel build`. The target checks
the files you declare and writes a JSON report, with enforced violations causing
the build to fail. Bazel can reuse a successful result from its local or remote
cache when the inputs and tool are unchanged.

Bazel caches each parse action separately, which lets a rule or data edit rerun
the checks without reparsing the sources. A source edit reruns only the parse
action that contains it, and Bylaws divides large source groups across several
actions.

## Add a lint target

Add `swift-bylaws` to your `MODULE.bazel` as shown in the
[README](https://github.com/theblixguy/swift-bylaws#run-checks-with-bazel), then
define a target in the root `BUILD.bazel`:

```starlark
load("@swift-bylaws//bazel:defs.bzl", "bylaws_lint")

bylaws_lint(
    name = "architecture",
    srcs = [
        "//Features/Orders:lint_sources",
        "//Features/Payments:lint_sources",
        "//Shared:lint_sources",
    ],
    rules = ["Bylaws.swift"],
    data = ["MODULE.bazel"],
)
```

Each package exposes the files that the rules should check. For example,
`Features/Orders/BUILD.bazel` can contain:

```starlark
filegroup(
    name = "lint_sources",
    srcs = glob(["**/*.swift"]),
    visibility = ["//visibility:public"],
)
```

Bazel globs stop at package boundaries, so list a filegroup from each package
whose files the rules should check. Include all relevant source files, even
when a change affects only one feature. Dependency and folder rules can need
files from other features to find a violation.

Run the target locally or in CI:

```sh
bazel build //:architecture
```

The target writes `bazel-bin/architecture.json` and reports violations and
warnings in the build output. Set `strict = True` on the target to fail the
build on advisory violations as well.

Sources use Swift 6 language mode by default. Set `swift_language_mode = "5"`
or `swift_language_mode = "4"` when the checked targets use an earlier mode.

## Tune parse actions

By default, each parse action reads at most 512 source files. Set
`sources_per_parse_action` when you want to divide the work into smaller or
larger actions:

```starlark
bylaws_lint(
    name = "architecture",
    srcs = ["//Sources:lint_sources"],
    rules = ["Bylaws.swift"],
    sources_per_parse_action = 256,
)
```

This setting changes how Bylaws divides the work between parse actions without
changing which files the rules check.

## Set the selection-cache budget

You can set `selection_cache_size = "32MiB"` on a `bylaws_lint` target to
change how much memory Bylaws can use to retain selections shared between
rules. If you omit the attribute or leave it empty, Bylaws uses the CLI's
default budget of 64MiB.

The value takes whole bytes or a case-insensitive `B`, `KB`, `MB`, `GB`,
`KiB`, `MiB` or `GiB` suffix. To turn off selection reuse, set
`selection_cache_size = "0"`.

This budget applies to retained selections within each lint action. Parsed
files and active rule evaluations use additional memory, so it is not a limit
on the process's total memory use. Bazel manages caching between actions.

## Include the files that rules read

The target preserves each file's path within its repository. A rule can select
`Features/Orders/**` in the sandbox as it does in the working directory. Files
from external repositories use their paths within those repositories too, and
conflicting paths cause the build to fail.

Use `data` for other files the rules read, including manifests, shared rule
sources, exported Bazel graphs and baselines:

```starlark
bylaws_lint(
    name = "architecture",
    srcs = ["//Sources:lint_sources"],
    rules = ["Config/Architecture.swift"],
    data = [
        "MODULE.bazel",
        "Package.swift",
        "Config/Bylaws.baseline.swift",
        "//Rules:shared_sources",
    ],
)
```

The `rules` list selects the rule files to run. When you omit it, Bylaws
discovers `Bylaws.swift` files among the declared inputs. Baseline discovery
also uses the included files, or you can select one with
`baseline = "Config/Bylaws.baseline.swift"`.

Include the root `MODULE.bazel` in `data` so `Codebase(root: .automatic())`
can find the project root inside the sandbox.

> Important: The sandbox contains only the declared inputs. Keep rule paths
> relative to the project and include every file a rule reads so Bazel can
> detect changes and reuse results correctly.

## Check generated files

Add the generating target to `srcs` alongside the checked-in files:

```starlark
bylaws_lint(
    name = "architecture",
    srcs = [
        "//Sources:lint_sources",
        "//Schema:generated_swift",
    ],
    rules = ["Bylaws.swift"],
    data = ["MODULE.bazel"],
)
```

Bazel runs the generator before the lint action. An output declared as
`Schema/Models/Order.swift` appears at that path to the rules, without the
`bazel-out` prefix. Generated directories work the same way, including their
contents. Rules can check the generated code and folder layout together with
the checked-in source. Bazel presents a generated directory as one input, so
Bylaws parses it in one action.

A generated directory must have its own path, separate from other inputs.
For example, use `Sources/Generated` when checked-in files use `Sources/App`.

For a different layout, use `copy_to_directory` from
[bazel_lib](https://github.com/bazel-contrib/bazel-lib) to arrange the generated
files, then pass that target in `srcs`. Its output directory becomes part of
the path that the rules see.

## Checks that need compiler data

The build target runs with `--source-only` and rejects compiler-index queries.
Run those checks after the compiler has produced an index:

```sh
bazel run @swift-bylaws//:bylaws -- lint --rules Config/IndexRules.swift
```

You can use the same command to record a baseline. See
<doc:RunningRulesFromTheCLI> for the CLI options and <doc:BazelDependencies>
for rules that read an exported Bazel dependency graph.
