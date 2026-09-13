# Running rules during builds

Check source-based architectural rules before SwiftPM compiles a target.

## Overview

You can use `BylawsBuildToolPlugin` to fail a SwiftPM build when source code
breaks an enforced rule, without installing `bylaws` separately.

> Important: Use `swift build --disable-build-manifest-caching` locally and in
> CI. Without that flag, SwiftPM can reuse the build plan and skip the check
> after a source edit.

## Add the plugin

Add Bylaws as a package dependency, then attach the plugin to any one of the
targets included in your build:

```swift
.executableTarget(
  name: "App",
  plugins: [
    .plugin(name: "BylawsBuildToolPlugin", package: "swift-bylaws"),
  ]
)
```

Put `Bylaws.swift` at the package root. It can use the same rules and shared
rule packages as the command plugin. See <doc:RunningRulesFromTheCLI> for the
supported Swift subset and shared-package setup.

Run the build with the required flag, both locally and in CI:

```sh
swift build --disable-build-manifest-caching
```

The plugin checks the source selected by each rule, including source in other
targets, so attaching it once per package avoids repeated checks. Its rules run
whenever the build includes that target and uses the flag above.

Use the plugin with SwiftPM command-line builds. It cannot attach directly to
an Xcode project target.

## Build results

The build fails on enforced violations, stale baseline entries or errors in
the rules, with a file and line number to help you find the problem.

Advisory violations let the build pass, but their warnings are hidden in
SwiftPM's build output. To see them, run the command plugin:

```sh
swift package --allow-writing-to-package-directory bylaws
```

You can use the command plugin to create or update a baseline, which both
plugins apply on later runs.

Compiler-index queries need a completed build, so keep those rules in a separate
file such as `Config/IndexRules.swift` and run them after the build. The build
plugin rejects them if they are included in its rules:

```sh
swift package --allow-writing-to-package-directory bylaws --rules Config/IndexRules.swift
```
