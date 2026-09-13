import BylawsSemantics

extension RuntimeEvaluator {
  func targetMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest.Target
  ) -> RuntimeValue? {
    switch name {
    case .name: .string(value.name)
    case .kind: .member(naming: value.kind)
    case .dependencies:
      manifestList(value.dependencies) {
        .model(.manifest(.targetDependency($0)))
      }
    case .dependencyNames: manifestStrings(value.dependencyNames)
    case .path: optionalString(value.path)
    case .excludedPaths: manifestStrings(value.excludedPaths)
    case .sources: .model(.manifest(.targetSourceSelection(value.sources)))
    case .resources:
      manifestList(value.resources) { .model(.manifest(.targetResource($0))) }
    case .publicHeadersPath: optionalString(value.publicHeadersPath)
    case .packageAccess: .boolean(value.packageAccess)
    case .buildSettings:
      manifestList(value.buildSettings) { .model(.manifest(.targetSetting($0)))
      }
    case .plugins:
      manifestList(value.plugins) { .model(.manifest(.targetPluginUsage($0))) }
    case .binarySource:
      optionalModel(value.binarySource) { .manifest(.binarySource($0)) }
    case .pkgConfig: optionalString(value.pkgConfig)
    case .providers:
      manifestList(value.providers) {
        .model(.manifest(.targetSystemPackageProvider($0)))
      }
    case .pluginCapability:
      optionalModel(
        value.pluginCapability,
        { .manifest(.pluginCapability($0)) }
      )
    case .unresolvedValues:
      modelArray(
        value.unresolvedValues,
        { .manifest(.unresolvedValue($0)) }
      )
    case .isComplete: .boolean(value.isComplete)
    case .isTest: .boolean(value.isTest)
    case .isPlugin: .boolean(value.isPlugin)
    case .moduleName: .string(value.moduleName)
    case .sourceDirectory: .string(value.sourceDirectory)
    default: nil
    }
  }

  func targetDependencyMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest.Target.Dependency
  ) -> RuntimeValue? {
    switch name {
    case .name: .string(value.name)
    case .kind: .member(naming: value.kind)
    case .packageName: optionalString(value.packageName)
    case .condition:
      optionalModel(value.condition) { .manifest(.condition($0)) }
    case .unresolvedValues:
      modelArray(
        value.unresolvedValues,
        { .manifest(.unresolvedValue($0)) }
      )
    case .isComplete: .boolean(value.isComplete)
    default: nil
    }
  }

  func sourceSelectionMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest.Target.SourceSelection
  ) -> RuntimeValue? {
    switch name {
    case .kind:
      if case .automatic = value { .member(.constant(.automatic)) }
      else { .member(.constant(.explicit)) }
    case .paths:
      if case let .explicit(paths) = value {
        .optional(manifestStrings(paths))
      } else {
        .optional(nil)
      }
    case .isComplete: .boolean(value.isComplete)
    default: nil
    }
  }

  func resourceMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest.Target.Resource
  ) -> RuntimeValue? {
    switch name {
    case .path: .string(value.path)
    case .rule: .member(naming: value.rule)
    case .localization: optionalString(value.localization)
    default: nil
    }
  }

  func settingMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest.Target.Setting
  ) -> RuntimeValue? {
    let fields = settingFields(value.value)
    return switch name {
    case .tool: .member(naming: value.tool)
    case .valueKind: .member(named: fields.kind)
    case .name: optionalString(fields.name)
    case .value: optionalString(fields.value)
    case .arguments: .array(fields.arguments.map(RuntimeValue.string))
    case .warningLevel: optionalMember(fields.warningLevel)
    case .defaultIsolation: optionalMember(fields.defaultIsolation)
    case .condition:
      optionalModel(value.condition) { .manifest(.condition($0)) }
    case .usesUnsafeFlags: .boolean(value.usesUnsafeFlags)
    default: nil
    }
  }

  func pluginUsageMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest.Target.PluginUsage
  ) -> RuntimeValue? {
    switch name {
    case .name: .string(value.name)
    case .packageName: optionalString(value.packageName)
    default: nil
    }
  }

  func binarySourceMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest.Target.BinarySource
  ) -> RuntimeValue? {
    switch (name, value) {
    case (.kind, .path): .member(.constant(.path))
    case (.kind, .remote): .member(.constant(.remote))
    case let (.path, .path(path)): .optional(.string(path))
    case (.path, .remote): .optional(nil)
    case let (.sourceLocation, .remote(url, _)): .optional(.string(url))
    case (.sourceLocation, .path): .optional(nil)
    case let (.checksum, .remote(_, checksum)): .optional(.string(checksum))
    case (.checksum, .path): .optional(nil)
    default: nil
    }
  }

  func providerMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest.Target.SystemPackageProvider
  ) -> RuntimeValue? {
    switch name {
    case .kind: .member(naming: value.kind)
    case .packages: .array(value.packages.map(RuntimeValue.string))
    default: nil
    }
  }

  func pluginCapabilityMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest.Target.PluginCapability
  ) -> RuntimeValue? {
    switch (name, value) {
    case (.kind, .buildTool): .member(.constant(.buildTool))
    case (.kind, .command): .member(.constant(.command))
    case (.intent, .buildTool): .optional(nil)
    case let (.intent, .command(intent, _)):
      .optional(.model(.manifest(.pluginIntent(intent))))
    case (.permissions, .buildTool): .array([])
    case let (.permissions, .command(_, permissions)):
      modelArray(permissions) { .manifest(.pluginPermission($0)) }
    default: nil
    }
  }

  func pluginIntentMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest.Target.PluginIntent
  ) -> RuntimeValue? {
    switch (name, value) {
    case (
      .kind,
      .documentationGeneration
    ): .member(.constant(.documentationGeneration))
    case (
      .kind,
      .sourceCodeFormatting
    ): .member(.constant(.sourceCodeFormatting))
    case (.kind, .custom): .member(.constant(.custom))
    case let (.verb, .custom(verb, _)): .optional(.string(verb))
    case (.verb, _): .optional(nil)
    case let (.description, .custom(_, description)):
      .optional(.string(description))
    case (.description, _): .optional(nil)
    default: nil
    }
  }

  func pluginPermissionMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest.Target.PluginPermission
  ) -> RuntimeValue? {
    switch (name, value) {
    case (.kind, .writeToPackageDirectory):
      .member(.constant(.writeToPackageDirectory))
    case (.kind, .allowNetworkConnections):
      .member(.constant(.allowNetworkConnections))
    case let (.reason, .writeToPackageDirectory(reason)):
      .string(reason)
    case let (.reason, .allowNetworkConnections(_, reason)):
      .string(reason)
    case (.networkScope, .writeToPackageDirectory): .optional(nil)
    case let (.networkScope, .allowNetworkConnections(scope, _)):
      .optional(.model(.manifest(.networkScope(scope))))
    default: nil
    }
  }

  func networkScopeMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest.Target.NetworkScope
  ) -> RuntimeValue? {
    switch (name, value) {
    case (.kind, .none): .member(.constant(.none))
    case (.kind, .local): .member(.constant(.local))
    case (.kind, .all): .member(.constant(.all))
    case (.kind, .docker): .member(.constant(.docker))
    case (.kind, .unixDomainSocket): .member(.constant(.unixDomainSocket))
    case let (.ports, .local(ports)), let (.ports, .all(ports)):
      .optional(.model(.manifest(.networkPorts(ports))))
    case (.ports, _): .optional(nil)
    default: nil
    }
  }

  func networkPortsMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest.Target.NetworkPorts
  ) -> RuntimeValue? {
    switch (name, value) {
    case (.kind, .values): .member(.constant(.values))
    case (.kind, .range): .member(.constant(.range))
    case let (.values, .values(ports)):
      .optional(.array(ports.map(RuntimeValue.integer)))
    case (.values, .range): .optional(nil)
    case let (.lowerBound, .range(from, _)): .optional(.integer(from))
    case (.lowerBound, .values): .optional(nil)
    case let (.upperBound, .range(_, upTo)): .optional(.integer(upTo))
    case (.upperBound, .values): .optional(nil)
    default: nil
    }
  }

  private func settingFields(
    _ value: PackageManifest.Target.Setting.Value
  ) -> SettingFields {
    switch value {
    case let .define(name, value):
      SettingFields("define", name: name, value: value)
    case let .unsafeFlags(arguments):
      SettingFields("unsafeFlags", arguments: arguments)
    case let .headerSearchPath(path):
      SettingFields("headerSearchPath", value: path)
    case let .enableUpcomingFeature(feature):
      SettingFields("enableUpcomingFeature", value: feature)
    case let .enableExperimentalFeature(feature):
      SettingFields("enableExperimentalFeature", value: feature)
    case .strictMemorySafety:
      SettingFields("strictMemorySafety")
    case let .interoperabilityMode(mode):
      SettingFields("interoperabilityMode", value: mode)
    case let .swiftLanguageMode(mode):
      SettingFields("swiftLanguageMode", value: mode)
    case let .treatAllWarnings(level):
      SettingFields("treatAllWarnings", warningLevel: level.rawValue)
    case let .treatWarning(warning, level):
      SettingFields(
        "treatWarning",
        name: warning,
        warningLevel: level.rawValue
      )
    case let .enableWarning(warning):
      SettingFields("enableWarning", name: warning)
    case let .disableWarning(warning):
      SettingFields("disableWarning", name: warning)
    case let .defaultIsolation(isolation):
      SettingFields(
        "defaultIsolation",
        defaultIsolation: isolation?.rawValue
      )
    case let .linkedLibrary(library):
      SettingFields("linkedLibrary", value: library)
    case let .linkedFramework(framework):
      SettingFields("linkedFramework", value: framework)
    }
  }
}

private struct SettingFields {
  let kind: String
  let name: String?
  let value: String?
  let arguments: [String]
  let warningLevel: String?
  let defaultIsolation: String?

  init(
    _ kind: String,
    name: String? = nil,
    value: String? = nil,
    arguments: [String] = [],
    warningLevel: String? = nil,
    defaultIsolation: String? = nil
  ) {
    self.kind = kind
    self.name = name
    self.value = value
    self.arguments = arguments
    self.warningLevel = warningLevel
    self.defaultIsolation = defaultIsolation
  }
}
