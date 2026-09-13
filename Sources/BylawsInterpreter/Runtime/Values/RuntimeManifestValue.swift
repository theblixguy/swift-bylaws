import BylawsSemantics

enum RuntimeManifestValue: Sendable, Equatable {
  case binarySource(PackageManifest.Target.BinarySource)
  case condition(PackageManifest.Condition)
  case dependency(PackageManifest.Dependency)
  case dependencyRequirement(PackageManifest.Dependency.Requirement)
  case dependencyTraitSelection(PackageManifest.Dependency.TraitSelection)
  case networkPorts(PackageManifest.Target.NetworkPorts)
  case networkScope(PackageManifest.Target.NetworkScope)
  case platform(PackageManifest.Platform)
  case platformVersion(PackageManifest.PlatformVersion)
  case pluginCapability(PackageManifest.Target.PluginCapability)
  case pluginIntent(PackageManifest.Target.PluginIntent)
  case pluginPermission(PackageManifest.Target.PluginPermission)
  case product(PackageManifest.Product)
  case target(PackageManifest.Target)
  case targetDependency(PackageManifest.Target.Dependency)
  case targetPluginUsage(PackageManifest.Target.PluginUsage)
  case targetResource(PackageManifest.Target.Resource)
  case targetSetting(PackageManifest.Target.Setting)
  case targetSourceSelection(PackageManifest.Target.SourceSelection)
  case targetSystemPackageProvider(PackageManifest.Target.SystemPackageProvider)
  case toolsVersion(PackageManifest.ToolsVersion)
  case trait(PackageManifest.Trait)
  case unresolvedValue(PackageManifest.UnresolvedValue)
  case version(PackageManifest.Version)

  var modelType: SupportedAPI.ModelType {
    switch self {
    case .binarySource: .manifestBinarySource
    case .condition: .manifestCondition
    case .dependency: .manifestDependency
    case .dependencyRequirement: .manifestDependencyRequirement
    case .dependencyTraitSelection: .manifestDependencyTraitSelection
    case .networkPorts: .manifestNetworkPorts
    case .networkScope: .manifestNetworkScope
    case .platform: .manifestPlatform
    case .platformVersion: .manifestPlatformVersion
    case .pluginCapability: .manifestPluginCapability
    case .pluginIntent: .manifestPluginIntent
    case .pluginPermission: .manifestPluginPermission
    case .product: .manifestProduct
    case .target: .manifestTarget
    case .targetDependency: .manifestTargetDependency
    case .targetPluginUsage: .manifestTargetPluginUsage
    case .targetResource: .manifestTargetResource
    case .targetSetting: .manifestTargetSetting
    case .targetSourceSelection: .manifestTargetSourceSelection
    case .targetSystemPackageProvider: .manifestTargetSystemPackageProvider
    case .toolsVersion: .manifestToolsVersion
    case .trait: .manifestTrait
    case .unresolvedValue: .manifestUnresolvedValue
    case .version: .manifestVersion
    }
  }

  var name: String? {
    switch self {
    case let .dependency(value): value.name
    case let .platform(value): value.name
    case let .product(value): value.name
    case let .target(value): value.name
    case let .targetDependency(value): value.name
    case let .targetPluginUsage(value): value.name
    case let .trait(value): value.name
    default: nil
    }
  }
}
