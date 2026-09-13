# Keep types in the right folders

Check a project's folder layout and the paths of its declarations.

## Overview

If each feature has `Models`, `ViewModels` and `Views` folders, you can check
the layout and require each type to live in the appropriate folder with one
set of rules. These rules also cover features you add later, and you can adapt
them for a module that shares these folders across features.

You can run these checks before a build through the CLI or an editor
integration as well as with your tests.
Follow <doc:GettingStarted> if you haven't installed Bylaws yet.

## One folder per feature

For example, `Orders` and `Profile` can follow the same layout:

```text
Sources/App/
  Orders/
    Models/
    ViewModels/
    Views/
  Profile/
    Models/
    ViewModels/
    Views/
```

Save the following rules as `Bylaws.swift` at your project root. They identify
view models by the `ViewModel` suffix, views by SwiftUI's `View` protocol and
models by an app-defined `FeatureModel` protocol. Change the paths and filters
to match your project.

```swift
import Bylaws
import Testing

let app = Codebase(including: ["Sources/App/**"])

let projectRules: [Rule] = [
  Rule("feature-folders", "Features contain Models, ViewModels and Views") {
    try await app.checkFolderLayout(
      matching: "Sources/App/*",
      containing: ["Models", "ViewModels", "Views"]
    )
  },
  Rule("view-model-folders", "View models belong in ViewModels") {
    try await app.types.suffixed("ViewModel")
      .violations(outsidePaths: "Sources/App/*/ViewModels/**")
  },
  Rule("view-folders", "Views belong in Views") {
    try await app.types.where(.conforms(to: "View"))
      .violations(outsidePaths: "Sources/App/*/Views/**")
  },
  Rule("model-folders", "Models belong in Models") {
    try await app.types.where(.conforms(to: "FeatureModel"))
      .violations(outsidePaths: "Sources/App/*/Models/**")
  },
]
```

Run the rules from the project root:

```sh
bylaws lint
```

A type named `OrderViewModel` in `Orders/Views/OrderViewModel.swift` fails the
view model rule. The folder rule reports a missing `Profile/Models` folder or
an extra `Profile/Helpers` folder, even when that folder is empty.

If a feature is missing `ViewModels`, create the folder and move its view
models there to fix both the layout and placement violations.

## Shared folders for the whole module

If every feature uses the same `Models`, `ViewModels` and `Views` folders,
replace the first two rules in `projectRules` with these versions, which omit
the feature wildcard:

```swift
Rule("app-folders", "App contains Models, ViewModels and Views") {
  try await app.checkFolderLayout(
    matching: "Sources/App",
    containing: ["Models", "ViewModels", "Views"]
  )
}

Rule("view-model-folders", "View models belong in ViewModels") {
  try await app.types.suffixed("ViewModel")
    .violations(outsidePaths: "Sources/App/ViewModels/**")
}
```

Apply the same change to the view and model paths. You can also use your own
folder names, such as `"View Models"`, in the folder list and path patterns.

## Check every Swift file

The type rules apply only to declarations that match their filters, so a helper
type that matches none of them can live in any folder. To require every Swift
file to live under `Models`, `ViewModels` or `Views`, add this rule to
`projectRules`:

```swift
Rule("feature-files", "Swift files belong in Models, ViewModels or Views") {
  try await app.files.violations(outsidePaths: [
    "Sources/App/*/Models/**",
    "Sources/App/*/ViewModels/**",
    "Sources/App/*/Views/**",
  ])
}
```

This rule reports a file such as `Sources/App/Orders/Helpers.swift`. A file
under `Orders/Views` passes, but its declarations must also pass the type rules.
For a module with shared folders, remove `*/` from each path.

## Match paths and folder names

`checkFolderLayout` reports missing or extra child directories in each matching
folder. If each feature must also contain `Resources`, add it to the list.
An empty list permits no child directories.

Path patterns match the full path relative to the codebase root. Use `*` for
one path segment and `**` for any number of segments, including none.
For example, `Views/**` permits `Views/Components/Button.swift`, while
`Views/*.swift` requires files to live directly in `Views`.

If the codebase includes other modules, add `.under("Sources/App")` before a
placement check to select declarations or files in this module. The
`.under(...)` and `.outside(...)` filters take literal directory paths, while
`outsidePaths:` takes glob patterns.

## Empty folders, exclusions and tests

The folder check includes empty directories and directories that contain only
resources. It ignores regular files and symbolic links, so a file or link
named `Views` cannot stand in for a required `Views` directory.

The folder check uses `matching:` to select directories independently of source
queries, so excluding `**/Resources/**` from those queries leaves the folder
check unchanged. Use `"."` to check the codebase root or a pattern to select
other folders. Bylaws warns if the pattern matches none.

Tests that use `.sources(...)` infer folders from the supplied file paths,
so use a temporary directory when you want to test empty folders.
