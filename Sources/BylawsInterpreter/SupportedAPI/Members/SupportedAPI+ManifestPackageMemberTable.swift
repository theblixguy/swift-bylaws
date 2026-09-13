extension SupportedAPI.ManifestMemberTable {
  var manifestListMembers: [RuntimeMemberAPI] { [
    SupportedAPI.property(
      .knownValues,
      on: manifestList,
      result: .manifestListKnownValues
    ),
    SupportedAPI.property(
      .conditionalValues,
      on: manifestList,
      result: .manifestListConditionalValues
    ),
    SupportedAPI.property(
      .possibleValues,
      on: manifestList,
      result: .manifestListPossibleValues
    ),
    SupportedAPI.property(
      .values,
      on: manifestList,
      result: .manifestListValues
    ),
    SupportedAPI.property(
      .unresolvedValues,
      on: manifestList,
      result: .fixed(array(.model(.manifestUnresolvedValue)))
    ),
    SupportedAPI.property(
      .isComplete,
      on: manifestList,
      result: .fixed(boolean)
    ),
  ] }

  var packageManifestMembers: [RuntimeMemberAPI] { [
    SupportedAPI.property(
      .name,
      on: [manifest],
      result: .fixed(optional(string))
    ),
    SupportedAPI.property(
      .toolsVersion,
      on: [manifest],
      result: .fixed(optional(.model(.manifestToolsVersion)))
    ),
    SupportedAPI.property(
      .defaultLocalization,
      on: [manifest],
      result: .fixed(optional(string))
    ),
    SupportedAPI.property(
      .platforms,
      on: [manifest],
      result: .fixed(list(.model(.manifestPlatform)))
    ),
    SupportedAPI.property(
      .products,
      on: [manifest],
      result: .fixed(list(.model(.manifestProduct)))
    ),
    SupportedAPI.property(
      .traits,
      on: [manifest],
      result: .fixed(list(.model(.manifestTrait)))
    ),
    SupportedAPI.property(
      .defaultTraitNames,
      on: [manifest],
      result: .fixed(list(string))
    ),
    SupportedAPI.property(
      .dependencies,
      on: [manifest],
      result: .fixed(list(.model(.manifestDependency)))
    ),
    SupportedAPI.property(
      .targets,
      on: [manifest],
      result: .fixed(list(.model(.manifestTarget)))
    ),
    SupportedAPI.property(
      .swiftLanguageModes,
      on: [manifest],
      result: .fixed(list(string))
    ),
    SupportedAPI.property(
      .cLanguageStandard,
      on: [manifest],
      result: .fixed(optional(string))
    ),
    SupportedAPI.property(
      .cxxLanguageStandard,
      on: [manifest],
      result: .fixed(optional(string))
    ),
    SupportedAPI.property(
      .unresolvedValues,
      on: [manifest],
      result: .fixed(array(.model(.manifestUnresolvedValue)))
    ),
    SupportedAPI.property(.isComplete, on: [manifest], result: .fixed(boolean)),

    SupportedAPI.method(
      .dependencies,
      on: [manifest],
      arguments: .exact([.init(.named, .exact(string))]),
      result: .fixed(list(.model(.manifestDependency)))
    ),
    SupportedAPI.method(
      .products,
      on: [manifest],
      arguments: .alternatives([
        [.init(.named, .exact(string))],
        [.init(.containing, .exact(.model(.manifestTarget)))],
      ]),
      result: .fixed(list(.model(.manifestProduct)))
    ),
    SupportedAPI.method(
      .targets,
      on: [manifest],
      arguments: .alternatives([
        [.init(.named, .exact(string))],
        [],
        [.init(.includingConditionalDependencies, .exact(boolean))],
      ]),
      result: .fixed(list(.model(.manifestTarget)))
    ),
    relationshipMethod(.directTargetDependencies),
    relationshipMethod(.transitiveTargetDependencies),
    testTargetMethod(),
  ] }

  var packageElementMembers: [RuntimeMemberAPI] { [
    SupportedAPI.property(
      .name,
      on: model(.manifestPlatform),
      result: .fixed(string)
    ),
    SupportedAPI.property(
      .minimumVersion,
      on: model(.manifestPlatform),
      result: .fixed(.model(.manifestPlatformVersion))
    ),

    SupportedAPI.property(
      .name,
      on: model(.manifestProduct),
      result: .fixed(string)
    ),
    SupportedAPI.property(
      .kind,
      on: model(.manifestProduct),
      result: .fixed(member(.productKind))
    ),
    SupportedAPI.property(
      .linkage,
      on: model(.manifestProduct),
      result: .fixed(optional(member(.libraryLinkage)))
    ),
    SupportedAPI.property(
      .targetNames,
      on: model(.manifestProduct),
      result: .fixed(list(string))
    ),
    SupportedAPI.property(
      .isComplete,
      on: model(.manifestProduct),
      result: .fixed(boolean)
    ),

    SupportedAPI.property(
      .name,
      on: model(.manifestTrait),
      result: .fixed(string)
    ),
    SupportedAPI.property(
      .description,
      on: model(.manifestTrait),
      result: .fixed(optional(string))
    ),
    SupportedAPI.property(
      .enabledTraitNames,
      on: model(.manifestTrait),
      result: .fixed(set(string))
    ),

    SupportedAPI.property(
      .name,
      on: model(.manifestDependency),
      result: .fixed(string)
    ),
    SupportedAPI.property(
      .sourceKind,
      on: model(.manifestDependency),
      result: .fixed(member(.dependencySource))
    ),
    SupportedAPI.property(
      .sourceLocation,
      on: model(.manifestDependency),
      result: .fixed(string)
    ),
    SupportedAPI.property(
      .requirement,
      on: model(.manifestDependency),
      result: .fixed(.model(.manifestDependencyRequirement))
    ),
    SupportedAPI.property(
      .traits,
      on: model(.manifestDependency),
      result: .fixed(list(.model(.manifestDependencyTraitSelection)))
    ),

    SupportedAPI.property(
      .kind,
      on: model(.manifestDependencyRequirement),
      result: .fixed(member(.dependencyRequirement))
    ),
    SupportedAPI.property(
      .isExactVersion,
      on: model(.manifestDependencyRequirement),
      result: .fixed(boolean)
    ),
    SupportedAPI.property(
      .minimumVersion,
      on: model(.manifestDependencyRequirement),
      result: .fixed(optional(.model(.manifestVersion)))
    ),
    SupportedAPI.property(
      .majorVersion,
      on: model(.manifestDependencyRequirement),
      result: .fixed(optional(integer))
    ),
    SupportedAPI.property(
      .lowerBound,
      on: model(.manifestDependencyRequirement),
      result: .fixed(optional(.model(.manifestVersion)))
    ),
    SupportedAPI.property(
      .upperBound,
      on: model(.manifestDependencyRequirement),
      result: .fixed(optional(.model(.manifestVersion)))
    ),
    SupportedAPI.property(
      .branch,
      on: model(.manifestDependencyRequirement),
      result: .fixed(optional(string))
    ),
    SupportedAPI.property(
      .revision,
      on: model(.manifestDependencyRequirement),
      result: .fixed(optional(string))
    ),

    SupportedAPI.property(
      .kind,
      on: model(.manifestDependencyTraitSelection),
      result: .fixed(member(.traitKind))
    ),
    SupportedAPI.property(
      .name,
      on: model(.manifestDependencyTraitSelection),
      result: .fixed(optional(string))
    ),
    SupportedAPI.property(
      .condition,
      on: model(.manifestDependencyTraitSelection),
      result: .fixed(optional(.model(.manifestCondition)))
    ),
  ] }

  var conditionMembers: [RuntimeMemberAPI] { [
    SupportedAPI.property(
      .platforms,
      on: model(.manifestCondition),
      result: .fixed(set(string))
    ),
    SupportedAPI.property(
      .configuration,
      on: model(.manifestCondition),
      result: .fixed(optional(member(.conditionConfiguration)))
    ),
    SupportedAPI.property(
      .traitNames,
      on: model(.manifestCondition),
      result: .fixed(set(string))
    ),
  ] }

  var versionMembers: [RuntimeMemberAPI] { [
    SupportedAPI.property(
      .major,
      on: model(.manifestVersion),
      result: .fixed(integer)
    ),
    SupportedAPI.property(
      .minor,
      on: model(.manifestVersion),
      result: .fixed(integer)
    ),
    SupportedAPI.property(
      .patch,
      on: model(.manifestVersion),
      result: .fixed(integer)
    ),
    SupportedAPI.property(
      .prereleaseIdentifiers,
      on: model(.manifestVersion),
      result: .fixed(array(string))
    ),
    SupportedAPI.property(
      .buildMetadataIdentifiers,
      on: model(.manifestVersion),
      result: .fixed(array(string))
    ),
    SupportedAPI.property(
      .description,
      on: model(.manifestVersion),
      result: .fixed(string)
    ),

    SupportedAPI.property(
      .components,
      on: model(.manifestToolsVersion),
      result: .fixed(array(integer))
    ),
    SupportedAPI.property(
      .description,
      on: model(.manifestToolsVersion),
      result: .fixed(string)
    ),
    SupportedAPI.property(
      .components,
      on: model(.manifestPlatformVersion),
      result: .fixed(array(integer))
    ),
    SupportedAPI.property(
      .description,
      on: model(.manifestPlatformVersion),
      result: .fixed(string)
    ),
  ] }

  var unresolvedValueMembers: [RuntimeMemberAPI] { [
    SupportedAPI.property(
      .field,
      on: model(.manifestUnresolvedValue),
      result: .fixed(string)
    ),
    SupportedAPI.property(
      .expression,
      on: model(.manifestUnresolvedValue),
      result: .fixed(string)
    ),
    SupportedAPI.property(
      .line,
      on: model(.manifestUnresolvedValue),
      result: .fixed(optional(integer))
    ),
    SupportedAPI.property(
      .column,
      on: model(.manifestUnresolvedValue),
      result: .fixed(optional(integer))
    ),
  ] }
}
