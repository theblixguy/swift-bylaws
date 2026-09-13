import BylawsSemantics

extension RuntimeEvaluator {
  func manifestMember(
    _ name: SupportedAPI.Member,
    _ model: RuntimeManifestValue
  ) -> RuntimeValue? {
    switch model {
    case let .platform(value): platformMember(name, value)
    case let .product(value): productMember(name, value)
    case let .trait(value): traitMember(name, value)
    case let .dependency(value): dependencyMember(name, value)
    case let .dependencyRequirement(value):
      requirementMember(name, value)
    case let .dependencyTraitSelection(value):
      traitSelectionMember(name, value)
    case let .target(value): targetMember(name, value)
    case let .targetDependency(value):
      targetDependencyMember(name, value)
    case let .targetSourceSelection(value):
      sourceSelectionMember(name, value)
    case let .targetResource(value): resourceMember(name, value)
    case let .targetSetting(value): settingMember(name, value)
    case let .targetPluginUsage(value): pluginUsageMember(name, value)
    case let .binarySource(value): binarySourceMember(name, value)
    case let .targetSystemPackageProvider(value):
      providerMember(name, value)
    case let .pluginCapability(value):
      pluginCapabilityMember(name, value)
    case let .pluginIntent(value): pluginIntentMember(name, value)
    case let .pluginPermission(value):
      pluginPermissionMember(name, value)
    case let .networkScope(value): networkScopeMember(name, value)
    case let .networkPorts(value): networkPortsMember(name, value)
    case let .condition(value): conditionMember(name, value)
    case let .version(value): versionMember(name, value)
    case let .toolsVersion(value): numericVersionMember(
        name,
        components: value.components,
        description: value.description
      )
    case let .platformVersion(value): numericVersionMember(
        name,
        components: value.components,
        description: value.description
      )
    case let .unresolvedValue(value):
      unresolvedValueMember(name, value)
    }
  }

  func packageManifestMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest
  ) -> RuntimeValue? {
    switch name {
    case .name: optionalString(value.name)
    case .toolsVersion:
      optionalModel(value.toolsVersion) { .manifest(.toolsVersion($0)) }
    case .defaultLocalization: optionalString(value.defaultLocalization)
    case .platforms:
      manifestList(value.platforms) { .model(.manifest(.platform($0))) }
    case .products:
      manifestList(value.products) { .model(.manifest(.product($0))) }
    case .traits: manifestList(value.traits) { .model(.manifest(.trait($0))) }
    case .defaultTraitNames: manifestStrings(value.defaultTraitNames)
    case .dependencies:
      manifestList(value.dependencies) { .model(.manifest(.dependency($0))) }
    case .targets:
      manifestList(value.targets) { .model(.manifest(.target($0))) }
    case .swiftLanguageModes: manifestStrings(value.swiftLanguageModes)
    case .cLanguageStandard: optionalString(value.cLanguageStandard)
    case .cxxLanguageStandard: optionalString(value.cxxLanguageStandard)
    case .unresolvedValues:
      modelArray(
        value.unresolvedValues,
        { .manifest(.unresolvedValue($0)) }
      )
    case .isComplete: .boolean(value.isComplete)
    default: nil
    }
  }

  func conditionMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest.Condition
  ) -> RuntimeValue? {
    switch name {
    case .platforms: stringSet(value.platforms)
    case .configuration: optionalMember(value.configuration?.rawValue)
    case .traitNames: stringSet(value.traitNames)
    default: nil
    }
  }

  func versionMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest.Version
  ) -> RuntimeValue? {
    switch name {
    case .major: .integer(value.major)
    case .minor: .integer(value.minor)
    case .patch: .integer(value.patch)
    case .prereleaseIdentifiers:
      .array(value.prereleaseIdentifiers.map(RuntimeValue.string))
    case .buildMetadataIdentifiers:
      .array(value.buildMetadataIdentifiers.map(RuntimeValue.string))
    case .description: .string(value.description)
    default: nil
    }
  }

  func numericVersionMember(
    _ name: SupportedAPI.Member,
    components: [Int],
    description: String
  ) -> RuntimeValue? {
    switch name {
    case .components: .array(components.map(RuntimeValue.integer))
    case .description: .string(description)
    default: nil
    }
  }

  func unresolvedValueMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest.UnresolvedValue
  ) -> RuntimeValue? {
    switch name {
    case .field: .string(value.field)
    case .expression: .string(value.expression)
    case .line: optionalInteger(value.line)
    case .column: optionalInteger(value.column)
    default: nil
    }
  }

  func manifestList<Element>(
    _ list: ManifestList<Element>,
    transform: (Element) -> RuntimeValue
  ) -> RuntimeValue {
    .manifestList(RuntimeManifestList(list, transform: transform))
  }

  func manifestStrings(_ list: ManifestList<String>) -> RuntimeValue {
    manifestList(list, transform: RuntimeValue.string)
  }

  func stringSet(_ values: Set<String>) -> RuntimeValue {
    .set(values.sorted().map(RuntimeValue.string))
  }

  func optionalMember(_ value: String?) -> RuntimeValue {
    .optional(value.flatMap(RuntimeValue.member(named:)))
  }

  func optionalInteger(_ value: Int?) -> RuntimeValue {
    .optional(value.map(RuntimeValue.integer))
  }
}
