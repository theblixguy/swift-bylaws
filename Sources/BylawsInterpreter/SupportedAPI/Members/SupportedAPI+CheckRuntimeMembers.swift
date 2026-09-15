extension SupportedAPI {
  static let checkRuntimeMembers: [RuntimeMemberAPI] = [
    property(
      .matchedFolders,
      on: [.model(.folderLayoutCheck)],
      result: .fixed(.array(.string))
    ),
    property(
      .missingFolders,
      on: [.model(.folderLayoutCheck)],
      result: .fixed(.array(.string))
    ),
    property(
      .unexpectedFolders,
      on: [.model(.folderLayoutCheck)],
      result: .fixed(.array(.string))
    ),
    property(
      .undeclared,
      on: [.model(.packageDependencyCheck)],
      result: .fixed(.array(.model(.undeclaredDependency)))
    ),
    property(
      .unused,
      on: [.model(.packageDependencyCheck)],
      result: .fixed(.array(.model(.unusedDependency)))
    ),
    property(
      .emptyTargets,
      on: [.model(.packageDependencyCheck)],
      result: .fixed(.array(.string))
    ),
    property(
      .checkedImportCount,
      on: [.model(.packageDependencyCheck)],
      result: .fixed(.integer)
    ),
    property(
      .isComplete,
      on: [.model(.packageDependencyCheck)],
      result: .fixed(.boolean)
    ),
    property(
      .unresolvedManifestValues,
      on: [.model(.packageDependencyCheck)],
      result: .fixed(.array(.model(.manifestUnresolvedValue)))
    ),
    property(
      .violations,
      on: [.model(.packageDependencyCheck)],
      result: .fixed(.violations(.importDeclaration))
    ),
    property(
      .unstable,
      on: [.model(.dependencyStabilityCheck)],
      result: .fixed(.array(.model(.unstableDependency)))
    ),
    property(
      .emptyTargets,
      on: [.model(.dependencyStabilityCheck)],
      result: .fixed(.array(.string))
    ),
    property(
      .checkedEdgeCount,
      on: [.model(.dependencyStabilityCheck)],
      result: .fixed(.integer)
    ),
    property(
      .isComplete,
      on: [.model(.dependencyStabilityCheck)],
      result: .fixed(.boolean)
    ),
    property(
      .unresolvedManifestValues,
      on: [.model(.dependencyStabilityCheck)],
      result: .fixed(.array(.model(.manifestUnresolvedValue)))
    ),
    property(
      .violations,
      on: [.model(.dependencyStabilityCheck)],
      result: .fixed(.violations(.importDeclaration))
    ),
    property(
      .emptyLayers,
      on: [.model(.layeringCheck)],
      result: .fixed(.array(.string))
    ),
    property(
      .missingImports,
      on: [.model(.layeringCheck)],
      result: .fixed(.array(.model(.missingImport)))
    ),
    property(
      .violations,
      on: [.model(.layeringCheck)],
      result: .fixed(.violations(.importDeclaration))
    ),
    property(
      .target,
      on: [.model(.undeclaredDependency)],
      result: .fixed(.string)
    ),
    property(
      .module,
      on: [.model(.undeclaredDependency)],
      result: .fixed(.string)
    ),
    property(
      .importDeclaration,
      on: [.model(.undeclaredDependency)],
      result: .fixed(.model(.importDeclaration))
    ),
    property(.target, on: [.model(.unusedDependency)], result: .fixed(.string)),
    property(.module, on: [.model(.unusedDependency)], result: .fixed(.string)),
    property(
      .target,
      on: [.model(.unstableDependency)],
      result: .fixed(.string)
    ),
    property(
      .importedTarget,
      on: [.model(.unstableDependency)],
      result: .fixed(.string)
    ),
    property(
      .importDeclaration,
      on: [.model(.unstableDependency)],
      result: .fixed(.model(.importDeclaration))
    ),
    property(
      .instability,
      on: [.model(.unstableDependency)],
      result: .fixed(.double)
    ),
    property(
      .importedInstability,
      on: [.model(.unstableDependency)],
      result: .fixed(.double)
    ),
    property(.layer, on: [.model(.missingImport)], result: .fixed(.string)),
    property(
      .requiredImport,
      on: [.model(.missingImport)],
      result: .fixed(.string)
    ),
    property(.message, on: [.model(.ruleWarning)], result: .fixed(.string)),
    property(
      .location,
      on: [.model(.ruleWarning)],
      result: .fixed(.model(.declarationLocation))
    ),
    property(
      .filePath,
      on: [.model(.declarationLocation)],
      result: .fixed(.string)
    ),
    property(
      .fileName,
      on: [.model(.declarationLocation)],
      result: .fixed(.string)
    ),
    property(
      .line,
      on: [.model(.declarationLocation)],
      result: .fixed(.integer)
    ),
    property(
      .column,
      on: [.model(.declarationLocation)],
      result: .fixed(.integer)
    ),
    property(
      .utf8Offset,
      on: [.model(.declarationLocation)],
      result: .fixed(.optional(.integer))
    ),
    property(
      .location,
      on: declarationReceivers.union([
        .model(.sourceFile), .model(.importDeclaration),
        .model(.extensionDeclaration), .model(.enumCase),
        .model(.functionCall), .model(.offender), .model(.indexReference),
      ]),
      result: .fixed(.model(.declarationLocation))
    ),
    method(
      .findings,
      on: [
        .violations, .findings, .ruleResults,
        .model(.packageDependencyCheck),
        .model(.dependencyStabilityCheck),
        .model(.layeringCheck),
        .model(.folderLayoutCheck),
      ],
      arguments: .exact([.init(
        .reportedAt,
        .exact(.model(.declarationLocation))
      )]),
      result: .fixed(.findings)
    ),
  ]
}
