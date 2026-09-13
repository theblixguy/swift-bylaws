import SwiftSyntax

struct ManifestTraitLists {
  let declarations: ManifestList<PackageManifest.Trait>
  let defaults: ManifestList<String>
}

enum ManifestTraitCollector {
  static func traits(
    from expression: ExprSyntax?,
    resolver: ManifestSyntaxResolver
  ) -> ManifestTraitLists {
    guard let expression else {
      return ManifestTraitLists(declarations: .init(), defaults: .init())
    }
    let elements = resolver.array(from: expression)
    var declarations: [PackageManifest.Trait] = []
    var defaultNames: [String] = []
    var declarationIssues = elements.unresolved.map {
      resolver.issue(field: "traits", expression: $0)
    }
    var defaultIssues = elements.unresolved.map {
      resolver.issue(field: "defaultTraitNames", expression: $0)
    }
    for expression in elements.known {
      if let name = resolver.string(from: expression) {
        declarations.append(PackageManifest.Trait(name: name))
        continue
      }
      guard let call = resolver.call(from: expression) else {
        declarationIssues.append(
          resolver.issue(field: "traits", expression: expression)
        )
        defaultIssues.append(
          resolver.issue(field: "defaultTraitNames", expression: expression)
        )
        continue
      }
      switch call.manifestCallName {
      case .trait:
        guard let name = resolver.string(
          from: call.manifestArgument(labelled: "name")
        ) else {
          declarationIssues.append(
            resolver.issue(field: "traits", expression: expression)
          )
          continue
        }
        let enabled = resolver.strings(
          from: call.manifestArgument(labelled: "enabledTraits")
        )
        let descriptionExpression = call.manifestArgument(
          labelled: "description"
        )
        let description = resolver.string(from: descriptionExpression)
        if let descriptionExpression, description == nil {
          declarationIssues.append(
            resolver.issue(
              field: "traits.\(name).description",
              expression: descriptionExpression
            )
          )
        }
        if !enabled.isComplete {
          declarationIssues.append(contentsOf: enabled.unresolvedValues.map {
            PackageManifest.UnresolvedValue(
              field: "traits.\(name).enabledTraitNames",
              expression: $0.expression
            )
          })
        }
        declarations.append(
          PackageManifest.Trait(
            name: name,
            description: description,
            enabledTraitNames: Set(enabled.knownValues)
          )
        )
      case .defaultTrait:
        let names = resolver.strings(
          from: call.manifestArgument(labelled: "enabledTraits")
        )
        defaultNames.append(contentsOf: names.knownValues)
        defaultIssues.append(contentsOf: names.unresolvedValues.map {
          PackageManifest.UnresolvedValue(
            field: "defaultTraitNames",
            expression: $0.expression
          )
        })
      default:
        declarationIssues.append(
          resolver.issue(field: "traits", expression: expression)
        )
        defaultIssues.append(
          resolver.issue(field: "defaultTraitNames", expression: expression)
        )
      }
    }
    return ManifestTraitLists(
      declarations: ManifestList(
        knownValues: declarations,
        unresolvedValues: declarationIssues
      ),
      defaults: ManifestList(
        knownValues: defaultNames,
        unresolvedValues: defaultIssues
      )
    )
  }
}
