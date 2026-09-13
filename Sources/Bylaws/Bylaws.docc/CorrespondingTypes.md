# Require corresponding types

Require a related type, such as a test suite for each repository.

## Overview

You can use a custom matcher to check that a declaration has a corresponding
type elsewhere in the project. For example, a repository can require a test
type, or each feature view can require its own view model.

## Give each repository a test type

For each repository, this rule requires a corresponding type under `Tests`,
such as `OrderRepositoryTests` for `OrderRepository`.

Save it in `Bylaws.swift` and run `bylaws lint`, or include the rule in your
Swift Testing rules:

```swift
import Bylaws
import Testing

let project = Codebase(including: ["Sources/**", "Tests/**"])

let projectRules: [Rule] = [
  Rule("repository-tests", "Repositories have tests") {
    let repositories = try await project.types
      .under("Sources").suffixed("Repository")
    let testNames = Set(try await project.types.under("Tests").map(\.name))
    let hasTests = Matcher<NominalType>("have a corresponding test type") {
      testNames.contains($0.name + "Tests")
    }
    return repositories.violations(of: hasTests)
  },
]
```

Use a separate codebase for each module if the project repeats type names
across modules. Otherwise, a test type in one module could satisfy the rule
for a repository in another.

## Keep a view and its view model in the same feature

For this layout, `Orders/Views/OrderView.swift` must have an
`OrderViewModel` under `Orders/ViewModels`. A view model in another feature
does not count:

```text
Sources/Features/Orders/
  Views/OrderView.swift
  ViewModels/OrderViewModel.swift
```

You can group the view models by feature folder and check each view against
the names in its group:

```swift
import Bylaws
import Foundation
import Testing

func featureFolder(_ type: NominalType) -> String {
  URL(fileURLWithPath: type.location.filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .path
}

let app = Codebase(including: ["Sources/Features/**"])
let rules: [Rule] = [
  Rule("feature-view-models", "Views have view models in the same feature") {
    let views = try await app.types.suffixed("View")
    let viewModels = try await app.types.suffixed("ViewModel")
    let namesByFeature = Dictionary(grouping: viewModels, by: featureFolder)
      .mapValues { Set($0.map(\.name)) }
    let hasViewModel =
      Matcher<NominalType>("have a view model in the same feature") { view in
        namesByFeature[featureFolder(view)]?.contains(view.name + "Model") == true
      }
    return views.violations(of: hasViewModel)
  },
]
```

The helper identifies the feature by the folder two levels above the file, so
keep the files directly inside `Views` and `ViewModels` or change the helper for
a deeper layout. You can combine it with <doc:FolderRules> to check that each
view model is inside `ViewModels`.

Change the name expression for other pairs, such as `OrderPresenter` and
`OrderPresenterTests`. The matcher can also check attributes or conformance
when a name alone does not identify the corresponding declaration.
