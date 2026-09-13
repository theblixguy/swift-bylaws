extension SupportedAPI.ManifestMemberTable {
  var targetMembers: [RuntimeMemberAPI] { [
    SupportedAPI.property(.name, on: [target], result: .fixed(string)),
    SupportedAPI.property(
      .kind,
      on: [target],
      result: .fixed(member(.targetKind))
    ),
    SupportedAPI.property(
      .dependencies,
      on: [target],
      result: .fixed(list(.model(.manifestTargetDependency)))
    ),
    SupportedAPI.property(
      .dependencyNames,
      on: [target],
      result: .fixed(list(string))
    ),
    SupportedAPI.property(
      .path,
      on: [target],
      result: .fixed(optional(string))
    ),
    SupportedAPI.property(
      .excludedPaths,
      on: [target],
      result: .fixed(list(string))
    ),
    SupportedAPI.property(
      .sources,
      on: [target],
      result: .fixed(.model(.manifestTargetSourceSelection))
    ),
    SupportedAPI.property(
      .resources,
      on: [target],
      result: .fixed(list(.model(.manifestTargetResource)))
    ),
    SupportedAPI.property(
      .publicHeadersPath,
      on: [target],
      result: .fixed(optional(string))
    ),
    SupportedAPI.property(
      .packageAccess,
      on: [target],
      result: .fixed(boolean)
    ),
    SupportedAPI.property(
      .buildSettings,
      on: [target],
      result: .fixed(list(.model(.manifestTargetSetting)))
    ),
    SupportedAPI.property(
      .plugins,
      on: [target],
      result: .fixed(list(.model(.manifestTargetPluginUsage)))
    ),
    SupportedAPI.property(
      .binarySource,
      on: [target],
      result: .fixed(optional(.model(.manifestBinarySource)))
    ),
    SupportedAPI.property(
      .pkgConfig,
      on: [target],
      result: .fixed(optional(string))
    ),
    SupportedAPI.property(
      .providers,
      on: [target],
      result: .fixed(list(.model(.manifestTargetSystemPackageProvider)))
    ),
    SupportedAPI.property(
      .pluginCapability,
      on: [target],
      result: .fixed(optional(.model(.manifestPluginCapability)))
    ),
    SupportedAPI.property(
      .unresolvedValues,
      on: [target],
      result: .fixed(array(.model(.manifestUnresolvedValue)))
    ),
    SupportedAPI.property(.isComplete, on: [target], result: .fixed(boolean)),
    SupportedAPI.property(.isTest, on: [target], result: .fixed(boolean)),
    SupportedAPI.property(.isPlugin, on: [target], result: .fixed(boolean)),
    SupportedAPI.property(.moduleName, on: [target], result: .fixed(string)),
    SupportedAPI.property(
      .sourceDirectory,
      on: [target],
      result: .fixed(string)
    ),

    SupportedAPI.property(
      .name,
      on: model(.manifestTargetDependency),
      result: .fixed(string)
    ),
    SupportedAPI.property(
      .kind,
      on: model(.manifestTargetDependency),
      result: .fixed(member(.targetDependencyKind))
    ),
    SupportedAPI.property(
      .packageName,
      on: model(.manifestTargetDependency),
      result: .fixed(optional(string))
    ),
    SupportedAPI.property(
      .condition,
      on: model(.manifestTargetDependency),
      result: .fixed(optional(.model(.manifestCondition)))
    ),
    SupportedAPI.property(
      .unresolvedValues,
      on: model(.manifestTargetDependency),
      result: .fixed(array(.model(.manifestUnresolvedValue)))
    ),
    SupportedAPI.property(
      .isComplete,
      on: model(.manifestTargetDependency),
      result: .fixed(boolean)
    ),

    SupportedAPI.property(
      .kind,
      on: model(.manifestTargetSourceSelection),
      result: .fixed(member(.sourceSelection))
    ),
    SupportedAPI.property(
      .paths,
      on: model(.manifestTargetSourceSelection),
      result: .fixed(optional(list(string)))
    ),
    SupportedAPI.property(
      .isComplete,
      on: model(.manifestTargetSourceSelection),
      result: .fixed(boolean)
    ),

    SupportedAPI.property(
      .path,
      on: model(.manifestTargetResource),
      result: .fixed(string)
    ),
    SupportedAPI.property(
      .rule,
      on: model(.manifestTargetResource),
      result: .fixed(member(.resourceRule))
    ),
    SupportedAPI.property(
      .localization,
      on: model(.manifestTargetResource),
      result: .fixed(optional(string))
    ),

    SupportedAPI.property(
      .tool,
      on: model(.manifestTargetSetting),
      result: .fixed(member(.settingTool))
    ),
    SupportedAPI.property(
      .valueKind,
      on: model(.manifestTargetSetting),
      result: .fixed(member(.settingValue))
    ),
    SupportedAPI.property(
      .name,
      on: model(.manifestTargetSetting),
      result: .fixed(optional(string))
    ),
    SupportedAPI.property(
      .value,
      on: model(.manifestTargetSetting),
      result: .fixed(optional(string))
    ),
    SupportedAPI.property(
      .arguments,
      on: model(.manifestTargetSetting),
      result: .fixed(array(string))
    ),
    SupportedAPI.property(
      .warningLevel,
      on: model(.manifestTargetSetting),
      result: .fixed(optional(member(.warningLevel)))
    ),
    SupportedAPI.property(
      .defaultIsolation,
      on: model(.manifestTargetSetting),
      result: .fixed(optional(member(.defaultIsolation)))
    ),
    SupportedAPI.property(
      .condition,
      on: model(.manifestTargetSetting),
      result: .fixed(optional(.model(.manifestCondition)))
    ),
    SupportedAPI.property(
      .usesUnsafeFlags,
      on: model(.manifestTargetSetting),
      result: .fixed(boolean)
    ),

    SupportedAPI.property(
      .name,
      on: model(.manifestTargetPluginUsage),
      result: .fixed(string)
    ),
    SupportedAPI.property(
      .packageName,
      on: model(.manifestTargetPluginUsage),
      result: .fixed(optional(string))
    ),

    SupportedAPI.property(
      .kind,
      on: model(.manifestBinarySource),
      result: .fixed(member(.binarySource))
    ),
    SupportedAPI.property(
      .path,
      on: model(.manifestBinarySource),
      result: .fixed(optional(string))
    ),
    SupportedAPI.property(
      .sourceLocation,
      on: model(.manifestBinarySource),
      result: .fixed(optional(string))
    ),
    SupportedAPI.property(
      .checksum,
      on: model(.manifestBinarySource),
      result: .fixed(optional(string))
    ),

    SupportedAPI.property(
      .kind,
      on: model(.manifestTargetSystemPackageProvider),
      result: .fixed(member(.systemPackageProviderKind))
    ),
    SupportedAPI.property(
      .packages,
      on: model(.manifestTargetSystemPackageProvider),
      result: .fixed(array(string))
    ),
  ] }

  var pluginMembers: [RuntimeMemberAPI] { [
    SupportedAPI.property(
      .kind,
      on: model(.manifestPluginCapability),
      result: .fixed(member(.pluginCapability))
    ),
    SupportedAPI.property(
      .intent,
      on: model(.manifestPluginCapability),
      result: .fixed(optional(.model(.manifestPluginIntent)))
    ),
    SupportedAPI.property(
      .permissions,
      on: model(.manifestPluginCapability),
      result: .fixed(array(.model(.manifestPluginPermission)))
    ),

    SupportedAPI.property(
      .kind,
      on: model(.manifestPluginIntent),
      result: .fixed(member(.pluginIntent))
    ),
    SupportedAPI.property(
      .verb,
      on: model(.manifestPluginIntent),
      result: .fixed(optional(string))
    ),
    SupportedAPI.property(
      .description,
      on: model(.manifestPluginIntent),
      result: .fixed(optional(string))
    ),

    SupportedAPI.property(
      .kind,
      on: model(.manifestPluginPermission),
      result: .fixed(member(.pluginPermission))
    ),
    SupportedAPI.property(
      .reason,
      on: model(.manifestPluginPermission),
      result: .fixed(string)
    ),
    SupportedAPI.property(
      .networkScope,
      on: model(.manifestPluginPermission),
      result: .fixed(optional(.model(.manifestNetworkScope)))
    ),

    SupportedAPI.property(
      .kind,
      on: model(.manifestNetworkScope),
      result: .fixed(member(.networkScope))
    ),
    SupportedAPI.property(
      .ports,
      on: model(.manifestNetworkScope),
      result: .fixed(optional(.model(.manifestNetworkPorts)))
    ),

    SupportedAPI.property(
      .kind,
      on: model(.manifestNetworkPorts),
      result: .fixed(member(.networkPorts))
    ),
    SupportedAPI.property(
      .values,
      on: model(.manifestNetworkPorts),
      result: .fixed(optional(array(integer)))
    ),
    SupportedAPI.property(
      .lowerBound,
      on: model(.manifestNetworkPorts),
      result: .fixed(optional(integer))
    ),
    SupportedAPI.property(
      .upperBound,
      on: model(.manifestNetworkPorts),
      result: .fixed(optional(integer))
    ),
  ] }
}
