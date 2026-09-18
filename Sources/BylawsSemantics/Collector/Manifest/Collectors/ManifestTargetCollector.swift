import BylawsSyntax

enum ManifestTargetCollector {
  static func targets(
    from expression: ExprSyntax?,
    resolver: ManifestSyntaxResolver
  ) -> ManifestList<PackageManifest.Target> {
    ManifestListDecoder.list(
      from: expression,
      field: "targets",
      resolver: resolver
    ) { target(from: $0, resolver: resolver) }
  }

  static func condition(
    from expression: ExprSyntax?,
    resolver: ManifestSyntaxResolver
  ) -> PackageManifest.Condition? {
    guard let expression,
          let call = resolver.call(from: expression),
          call.manifestCallName == .when
    else { return nil }
    let platforms = memberNameSet(
      from: call.manifestArgument(labelled: "platforms"),
      resolver: resolver
    )
    let traits = ManifestListDecoder.list(
      from: call.manifestArgument(labelled: "traits"),
      field: "condition.traits",
      resolver: resolver,
      nilMeansEmpty: true
    ) { resolver.string(from: $0) }
    let configurationExpression = call.manifestArgument(
      labelled: "configuration"
    )
    let configuration = resolver.memberName(from: configurationExpression)
      .flatMap(PackageManifest.Condition.Configuration.init(rawValue:))
    guard platforms.isComplete,
          traits.isComplete,
          configurationExpression == nil || configuration != nil
    else { return nil }
    return PackageManifest.Condition(
      platforms: Set(platforms.knownValues),
      configuration: configuration,
      traitNames: Set(traits.knownValues)
    )
  }

  static func target(
    from expression: ExprSyntax,
    resolver: ManifestSyntaxResolver
  ) -> PackageManifest.Target? {
    guard let call = resolver.call(from: expression),
          let kind = PackageManifest.Target.Kind(
            manifestCallName: call.manifestCallName
          ),
          let name = resolver.string(
            from: call.manifestArgument(labelled: "name")
          )
    else { return nil }

    var unresolved: [PackageManifest.UnresolvedValue] = []
    let path = resolvedString(
      labelled: "path",
      in: call,
      field: "targets.\(name).path",
      resolver: resolver,
      unresolved: &unresolved
    )
    let publicHeadersPath = resolvedString(
      labelled: "publicHeadersPath",
      in: call,
      field: "targets.\(name).publicHeadersPath",
      resolver: resolver,
      unresolved: &unresolved
    )
    let pkgConfig = resolvedString(
      labelled: "pkgConfig",
      in: call,
      field: "targets.\(name).pkgConfig",
      resolver: resolver,
      unresolved: &unresolved
    )
    let packageAccess = resolvedBool(
      labelled: "packageAccess",
      in: call,
      defaultValue: true,
      field: "targets.\(name).packageAccess",
      resolver: resolver,
      unresolved: &unresolved
    )

    let sources: PackageManifest.Target
      .SourceSelection = if let expression = call
      .manifestArgument(labelled: "sources"),
      !expression.is(NilLiteralExprSyntax.self)
    {
      .explicit(
        resolver.strings(from: expression)
          .assigningField("targets.\(name).sources")
      )
    } else {
      .automatic
    }

    let capabilityExpression = call.manifestArgument(labelled: "capability")
    let capability = ManifestPluginCollector.capability(
      from: capabilityExpression,
      resolver: resolver
    )
    if let capabilityExpression, capability == nil {
      unresolved.append(
        resolver.issue(
          field: "targets.\(name).pluginCapability",
          expression: capabilityExpression
        )
      )
    }

    return PackageManifest.Target(
      name: name,
      dependencies: dependencies(
        from: call.manifestArgument(labelled: "dependencies"),
        field: "targets.\(name).dependencies",
        resolver: resolver
      ),
      path: path,
      kind: kind,
      excludedPaths: resolver.strings(
        from: call.manifestArgument(labelled: "exclude")
      ).assigningField("targets.\(name).excludedPaths"),
      sources: sources,
      resources: resources(
        from: call.manifestArgument(labelled: "resources"),
        field: "targets.\(name).resources",
        resolver: resolver
      ),
      publicHeadersPath: publicHeadersPath,
      packageAccess: packageAccess,
      buildSettings: ManifestBuildSettingCollector.settings(
        in: call,
        targetName: name,
        resolver: resolver
      ),
      plugins: ManifestPluginCollector.usages(
        from: call.manifestArgument(labelled: "plugins"),
        field: "targets.\(name).plugins",
        resolver: resolver
      ),
      binarySource: binarySource(
        from: call,
        resolver: resolver,
        unresolved: &unresolved,
        field: "targets.\(name).binarySource"
      ),
      pkgConfig: pkgConfig,
      providers: providers(
        from: call.manifestArgument(labelled: "providers"),
        field: "targets.\(name).providers",
        resolver: resolver
      ),
      pluginCapability: capability,
      unresolvedValues: unresolved
    )
  }

  private static func dependencies(
    from expression: ExprSyntax?,
    field: String,
    resolver: ManifestSyntaxResolver
  ) -> ManifestList<PackageManifest.Target.Dependency> {
    ManifestListDecoder.list(
      from: expression,
      field: field,
      resolver: resolver
    ) { expression in
      if let name = resolver.string(from: expression) {
        return PackageManifest.Target.Dependency(name: name)
      }
      guard let call = resolver.call(from: expression) else {
        return nil
      }
      let kind: PackageManifest.Target.Dependency.Kind
      switch call.manifestCallName {
      case .target: kind = .target
      case .product: kind = .product
      case .byName: kind = .byName
      default: return nil
      }
      guard let name = resolver.string(
        from: call.manifestArgument(labelled: "name")
          ?? call.manifestUnlabelledArgument()
      ) else { return nil }
      guard let aliases = resolver.stringDictionary(
        from: call.manifestArgument(labelled: "moduleAliases")
      ) else { return nil }
      var unresolved: [PackageManifest.UnresolvedValue] = []
      let packageExpression = call.manifestArgument(labelled: "package")
      let packageName = resolver.string(from: packageExpression)
      if let packageExpression, packageName == nil {
        unresolved.append(
          resolver.issue(
            field: "targetDependency.packageName",
            expression: packageExpression
          )
        )
      }
      let conditionExpression = call.manifestArgument(labelled: "condition")
      let parsedCondition = condition(
        from: conditionExpression,
        resolver: resolver
      )
      guard conditionExpression == nil || parsedCondition != nil else {
        return nil
      }
      return PackageManifest.Target.Dependency(
        name: name,
        kind: kind,
        packageName: packageName,
        moduleAliases: aliases,
        condition: parsedCondition,
        unresolvedValues: unresolved
      )
    }
  }

  private static func resources(
    from expression: ExprSyntax?,
    field: String,
    resolver: ManifestSyntaxResolver
  ) -> ManifestList<PackageManifest.Target.Resource> {
    ManifestListDecoder.list(
      from: expression,
      field: field,
      resolver: resolver,
      nilMeansEmpty: true
    ) { expression in
      guard let call = resolver.call(from: expression),
            let path = resolver.string(
              from: call.manifestUnlabelledArgument()
                ?? call.manifestArgument(labelled: "path")
            )
      else { return nil }
      let rule: PackageManifest.Target.Resource.BuildRule
      switch call.manifestCallName {
      case .process: rule = .process
      case .copy: rule = .copy
      case .embedInCode: rule = .embedInCode
      default: return nil
      }
      let localizationExpression = call.manifestArgument(
        labelled: "localization"
      )
      let localization = resolver.memberName(from: localizationExpression)
      guard localizationExpression == nil || localization != nil else {
        return nil
      }
      return PackageManifest.Target.Resource(
        path: path,
        rule: rule,
        localization: localization
      )
    }
  }

  private static func binarySource(
    from call: FunctionCallExprSyntax,
    resolver: ManifestSyntaxResolver,
    unresolved: inout [PackageManifest.UnresolvedValue],
    field: String
  ) -> PackageManifest.Target.BinarySource? {
    guard call.manifestCallName == .binaryTarget else { return nil }
    if let expression = call.manifestArgument(labelled: "path") {
      if let path = resolver.string(from: expression) { return .path(path) }
      unresolved.append(resolver.issue(field: field, expression: expression))
      return nil
    }
    guard let urlExpression = call.manifestArgument(labelled: "url"),
          let checksumExpression = call.manifestArgument(labelled: "checksum"),
          let url = resolver.string(from: urlExpression),
          let checksum = resolver.string(from: checksumExpression)
    else {
      unresolved.append(resolver.issue(field: field, expression: call))
      return nil
    }
    return .remote(url: url, checksum: checksum)
  }

  private static func providers(
    from expression: ExprSyntax?,
    field: String,
    resolver: ManifestSyntaxResolver
  ) -> ManifestList<PackageManifest.Target.SystemPackageProvider> {
    ManifestListDecoder.list(
      from: expression,
      field: field,
      resolver: resolver,
      nilMeansEmpty: true
    ) { expression in
      guard let call = resolver.call(from: expression),
            let writtenKind = memberName(from: call.calledExpression),
            let kind = PackageManifest.Target.SystemPackageProvider.Kind(
              rawValue: writtenKind
            )
      else { return nil }
      let packages = resolver.strings(from: call.manifestUnlabelledArgument())
      guard let resolved = packages.values else { return nil }
      return PackageManifest.Target.SystemPackageProvider(
        kind: kind,
        packages: resolved
      )
    }
  }

  private static func memberNameSet(
    from expression: ExprSyntax?,
    resolver: ManifestSyntaxResolver
  ) -> ManifestList<String> {
    ManifestListDecoder.list(
      from: expression,
      field: "condition.platforms",
      resolver: resolver,
      nilMeansEmpty: true
    ) { resolver.memberName(from: $0) }
  }

  private static func resolvedString(
    labelled label: String,
    in call: FunctionCallExprSyntax,
    field: String,
    resolver: ManifestSyntaxResolver,
    unresolved: inout [PackageManifest.UnresolvedValue]
  ) -> String? {
    guard let expression = call.manifestArgument(labelled: label) else {
      return nil
    }
    if let value = resolver.string(from: expression) { return value }
    unresolved.append(resolver.issue(field: field, expression: expression))
    return nil
  }

  private static func resolvedBool(
    labelled label: String,
    in call: FunctionCallExprSyntax,
    defaultValue: Bool,
    field: String,
    resolver: ManifestSyntaxResolver,
    unresolved: inout [PackageManifest.UnresolvedValue]
  ) -> Bool {
    guard let expression = call.manifestArgument(labelled: label) else {
      return defaultValue
    }
    if let value = resolver.bool(from: expression) { return value }
    unresolved.append(resolver.issue(field: field, expression: expression))
    return defaultValue
  }
}

extension PackageManifest.Target.Kind {
  fileprivate init?(manifestCallName: ManifestCallName?) {
    switch manifestCallName {
    case .target: self = .regular
    case .executableTarget: self = .executable
    case .macro: self = .macro
    case .testTarget: self = .test
    case .systemLibrary: self = .systemLibrary
    case .binaryTarget: self = .binary
    case .plugin: self = .plugin
    default: return nil
    }
  }
}
