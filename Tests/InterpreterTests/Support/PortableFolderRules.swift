import Bylaws
import Foundation
import Testing

func featureFolder(_ type: NominalType) -> String {
  URL(fileURLWithPath: type.location.filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .path
}

func rulesForFeatureViews(_ app: Codebase) -> [Rule] {
  [
    Rule("feature-view-models", "Views have view models in the same feature") {
      let views = try await app.types.suffixed("View")
      let viewModels = try await app.types.suffixed("ViewModel")
      let namesByFeature = Dictionary(grouping: viewModels, by: featureFolder)
        .mapValues { Set($0.map(\.name)) }
      let hasViewModel =
        Matcher<NominalType>("have a view model in the same feature") { view in
          namesByFeature[featureFolder(view)]?
            .contains(view.name + "Model") == true
        }
      return views.violations(of: hasViewModel)
    },
  ]
}
