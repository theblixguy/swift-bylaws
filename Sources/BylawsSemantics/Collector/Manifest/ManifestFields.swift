import BylawsSyntax

struct ManifestFields {
  var name: String?
  var defaultLocalization: String?
  var platforms: ManifestList<PackageManifest.Platform>
  var products: ManifestList<PackageManifest.Product>
  var traits: ManifestTraitLists
  var dependencies: ManifestList<PackageManifest.Dependency>
  var targets: ManifestList<PackageManifest.Target>
  var swiftLanguageModes: ManifestList<String>
  var cLanguageStandard: String?
  var cxxLanguageStandard: String?
  var unresolved: [PackageManifest.UnresolvedValue]

  init(
    call: FunctionCallExprSyntax,
    resolver: ManifestSyntaxResolver
  ) {
    unresolved = []
    name = resolver.string(from: call.manifestArgument(labelled: "name"))
    if name == nil, let expression = call.manifestArgument(labelled: "name") {
      unresolved.append(resolver.issue(field: "name", expression: expression))
    }

    defaultLocalization = resolver.string(
      from: call.manifestArgument(labelled: "defaultLocalization")
    )
    if defaultLocalization == nil,
       let expression = call.manifestArgument(labelled: "defaultLocalization")
    {
      unresolved.append(
        resolver.issue(field: "defaultLocalization", expression: expression)
      )
    }

    traits = ManifestTraitCollector.traits(
      from: call.manifestArgument(labelled: "traits"),
      resolver: resolver
    )
    platforms = ManifestPlatformCollector.platforms(
      from: call.manifestArgument(labelled: "platforms"),
      resolver: resolver
    )
    dependencies = ManifestDependencyCollector.dependencies(
      from: call.manifestArgument(labelled: "dependencies"),
      resolver: resolver
    )
    products = ManifestProductCollector.products(
      from: call.manifestArgument(labelled: "products"),
      resolver: resolver
    )
    targets = ManifestTargetCollector.targets(
      from: call.manifestArgument(labelled: "targets"),
      resolver: resolver
    )
    swiftLanguageModes = ManifestListDecoder.memberNames(
      from: call.manifestArgument(labelled: "swiftLanguageModes")
        ?? call.manifestArgument(labelled: "swiftLanguageVersions"),
      field: "swiftLanguageModes",
      resolver: resolver
    )

    let cStandardExpression = call.manifestArgument(
      labelled: "cLanguageStandard"
    )
    cLanguageStandard = resolver.memberName(from: cStandardExpression)
    if let cStandardExpression, cLanguageStandard == nil {
      unresolved.append(
        resolver.issue(
          field: "cLanguageStandard",
          expression: cStandardExpression
        )
      )
    }

    let cxxStandardExpression = call.manifestArgument(
      labelled: "cxxLanguageStandard"
    )
    cxxLanguageStandard = resolver.memberName(from: cxxStandardExpression)
    if let cxxStandardExpression, cxxLanguageStandard == nil {
      unresolved.append(
        resolver.issue(
          field: "cxxLanguageStandard",
          expression: cxxStandardExpression
        )
      )
    }
  }

  func manifest(
    toolsVersion: PackageManifest.ToolsVersion?,
    syntaxIssues: [PackageManifest.UnresolvedValue]
  ) -> PackageManifest {
    PackageManifest(
      name: name,
      toolsVersion: toolsVersion,
      defaultLocalization: defaultLocalization,
      platforms: platforms.adding(syntaxIssues),
      products: products.adding(syntaxIssues),
      traits: traits.declarations.adding(syntaxIssues),
      defaultTraitNames: traits.defaults.adding(syntaxIssues),
      dependencies: dependencies.adding(syntaxIssues),
      targets: targets.adding(syntaxIssues),
      swiftLanguageModes: swiftLanguageModes.adding(syntaxIssues),
      cLanguageStandard: cLanguageStandard,
      cxxLanguageStandard: cxxLanguageStandard,
      unresolvedValues: unresolved + syntaxIssues
    )
  }
}
