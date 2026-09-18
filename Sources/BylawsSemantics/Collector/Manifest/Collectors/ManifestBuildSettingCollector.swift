import BylawsSyntax

enum ManifestBuildSettingCollector {
  private enum Field: String, CaseIterable {
    case swiftSettings
    case cSettings
    case cxxSettings
    case linkerSettings

    var tool: PackageManifest.Target.Setting.Tool {
      switch self {
      case .swiftSettings: .swift
      case .cSettings: .c
      case .cxxSettings: .cxx
      case .linkerSettings: .linker
      }
    }
  }

  static func settings(
    in call: FunctionCallExprSyntax,
    targetName: String,
    resolver: ManifestSyntaxResolver
  ) -> ManifestList<PackageManifest.Target.Setting> {
    var values: [PackageManifest.Target.Setting] = []
    var unresolved: [PackageManifest.UnresolvedValue] = []
    for field in Field.allCases {
      let parsed = ManifestListDecoder.list(
        from: call.manifestArgument(labelled: field.rawValue),
        field: "targets.\(targetName).\(field.rawValue)",
        resolver: resolver,
        nilMeansEmpty: true
      ) { setting(from: $0, tool: field.tool, resolver: resolver) }
      values.append(contentsOf: parsed.knownValues)
      unresolved.append(contentsOf: parsed.unresolvedValues)
    }
    return ManifestList(knownValues: values, unresolvedValues: unresolved)
  }

  private static func setting(
    from expression: ExprSyntax,
    tool: PackageManifest.Target.Setting.Tool,
    resolver: ManifestSyntaxResolver
  ) -> PackageManifest.Target.Setting? {
    guard let call = resolver.call(from: expression) else { return nil }
    let first = call.manifestUnlabelledArgument()
    let conditionIndex = switch call.manifestCallName {
    case .strictMemorySafety, .treatAllWarnings: 0
    default: 1
    }
    let conditionExpression = call.manifestArgument(labelled: "condition")
      ?? call.manifestUnlabelledArgument(at: conditionIndex)
    let parsedCondition = ManifestTargetCollector.condition(
      from: conditionExpression,
      resolver: resolver
    )
    guard conditionExpression == nil || parsedCondition != nil
    else { return nil }
    let value: PackageManifest.Target.Setting.Value
    switch call.manifestCallName {
    case .define:
      guard let name = resolver.string(from: first) else { return nil }
      let valueExpression = call.manifestArgument(labelled: "to")
      let definedValue = resolver.string(from: valueExpression)
      guard valueExpression == nil || definedValue != nil else { return nil }
      value = .define(name: name, value: definedValue)
    case .unsafeFlags:
      let flags = resolver.strings(from: first)
      guard let resolved = flags.values else { return nil }
      value = .unsafeFlags(resolved)
    case .headerSearchPath:
      guard let path = resolver.string(from: first) else { return nil }
      value = .headerSearchPath(path)
    case .enableUpcomingFeature:
      guard let name = resolver.string(from: first) else { return nil }
      value = .enableUpcomingFeature(name)
    case .enableExperimentalFeature:
      guard let name = resolver.string(from: first) else { return nil }
      value = .enableExperimentalFeature(name)
    case .strictMemorySafety: value = .strictMemorySafety
    case .interoperabilityMode:
      guard let mode = resolver.memberName(from: first) else { return nil }
      value = .interoperabilityMode(mode)
    case .swiftLanguageMode, .swiftLanguageVersion:
      guard let mode = resolver.memberName(from: first) else { return nil }
      value = .swiftLanguageMode(mode)
    case .treatAllWarnings:
      guard let level = warningLevel(
        from: call.manifestArgument(labelled: "as"),
        resolver: resolver
      ) else { return nil }
      value = .treatAllWarnings(as: level)
    case .treatWarning:
      guard let warning = resolver.string(from: first),
            let level = warningLevel(
              from: call.manifestArgument(labelled: "as"),
              resolver: resolver
            )
      else { return nil }
      value = .treatWarning(warning, as: level)
    case .enableWarning:
      guard let warning = resolver.string(from: first) else { return nil }
      value = .enableWarning(warning)
    case .disableWarning:
      guard let warning = resolver.string(from: first) else { return nil }
      value = .disableWarning(warning)
    case .defaultIsolation:
      if first?.is(NilLiteralExprSyntax.self) == true {
        value = .defaultIsolation(nil)
      } else if isMainActorType(first, resolver: resolver) {
        value = .defaultIsolation(.mainActor)
      } else {
        return nil
      }
    case .linkedLibrary:
      guard let library = resolver.string(from: first) else { return nil }
      value = .linkedLibrary(library)
    case .linkedFramework:
      guard let framework = resolver.string(from: first) else { return nil }
      value = .linkedFramework(framework)
    default: return nil
    }
    return PackageManifest.Target.Setting(
      tool: tool,
      value: value,
      condition: parsedCondition
    )
  }

  private static func isMainActorType(
    _ expression: ExprSyntax?,
    resolver: ManifestSyntaxResolver
  ) -> Bool {
    guard let expression,
          let member = resolver.resolvedExpression(from: expression)?
          .as(MemberAccessExprSyntax.self),
          member.declName.baseName.text == "self",
          member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text
          == "MainActor"
    else { return false }
    return true
  }

  private static func warningLevel(
    from expression: ExprSyntax?,
    resolver: ManifestSyntaxResolver
  ) -> PackageManifest.Target.Setting.WarningLevel? {
    resolver.memberName(from: expression).flatMap(
      PackageManifest.Target.Setting.WarningLevel.init(rawValue:)
    )
  }
}
