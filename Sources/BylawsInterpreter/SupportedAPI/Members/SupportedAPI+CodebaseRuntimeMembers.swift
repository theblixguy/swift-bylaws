extension SupportedAPI {
  static let codebaseRuntimeMembers: [RuntimeMemberAPI] = [
    property(.name, on: [.dependencyGroup], result: .fixed(.string)),
    property(.files, on: [.dependencyGroup], result: .fixed(.array(.string))),
    method(
      .dependencyGroups,
      on: [.codebase],
      arguments: .exact([.init(.inFoldersMatching, .exact(.string))]),
      result: .fixed(.array(.dependencyGroup)),
      canSuspend: true
    ),
    method(
      .checkFolderLayout,
      on: [.codebase],
      arguments: .exact([
        .init(.matching, .exact(.string)),
        .init(.containing, .exact(.array(.string))),
      ]),
      result: .fixed(.model(.folderLayoutCheck)),
      canSuspend: true
    ),
    codebaseSelection(.files, family: .file),
    codebaseSelection(.classes, family: .class),
    codebaseSelection(.actors, family: .actor),
    codebaseSelection(.structs, family: .struct),
    codebaseSelection(.enums, family: .enum),
    codebaseSelection(.types, family: .nominalType),
    codebaseSelection(.protocols, family: .protocol),
    codebaseSelection(.extensions, family: .extension),
    codebaseSelection(.functions, family: .function),
    codebaseSelection(.properties, family: .property),
    codebaseSelection(.initializers, family: .initializer),
    codebaseSelection(.imports, family: .import),
    codebaseSelection(.typealiases, family: .typealias),
    codebaseSelection(.calls, family: .functionCall),
    property(
      .packageManifest,
      on: [.codebase],
      result: .fixed(.model(.packageManifest)),
      canSuspend: true
    ),
    method(
      .importGraph,
      on: [.codebase],
      arguments: .exact([]),
      result: .fixed(.model(.importGraph)),
      canSuspend: true
    ),
  ]

  static let projectIndexRuntimeMembers: [RuntimeMemberAPI] = [
    method(
      .checkDependencies,
      on: [.codebase],
      arguments: .indexQuery(
        leading: [
          .init(.from, .exact(.array(.string))),
          .init(.allowingReferencesTo, .exact(.array(.string))),
        ],
        optional: [
          .init(.allowingWithinFoldersMatching, .exact(.optional(.string))),
          .init(.modules, .exact(.optional(.array(.string)))),
          .init(.unitOutputFiles, .exact(.optional(.array(.string)))),
        ]
      ),
      result: .fixed(.findings),
      canSuspend: true
    ),
    method(
      .checkDependencyCycles,
      on: [.codebase],
      arguments: indexArguments(leading: [
        .init(.between, .exact(.array(.dependencyGroup))),
      ]),
      result: .fixed(.findings),
      canSuspend: true
    ),
    method(
      .projectIndex,
      on: [.codebase],
      arguments: indexArguments(leading: []),
      result: .fixed(.projectIndex),
      canSuspend: true
    ),
    method(
      .indexedFindings,
      on: [.codebase],
      arguments: indexArguments(
        leading: [.init(.of, .exact(.layering))]
      ),
      result: .fixed(.findings),
      canSuspend: true
    ),
    codebaseIndexMethod(.conformers, label: .of),
    codebaseIndexMethod(.directConformers, label: .of),
    codebaseIndexMethod(.references, label: .to),
    codebaseIndexMethod(.definitions, label: .of),
    codebaseIndexMethod(.occurrences, label: .of),
    codebasePackageMethod(
      .checkPackageDependencies,
      result: .packageDependencyCheck
    ),
    codebasePackageMethod(
      .checkDependencyStability,
      result: .dependencyStabilityCheck
    ),
    method(
      .checkLayering,
      on: [.codebase],
      arguments: .exact([.init(nil, .exact(.layering))]),
      result: .fixed(.model(.layeringCheck)),
      canSuspend: true
    ),

    projectIndexMethod(.conformers, label: .of),
    projectIndexMethod(.directConformers, label: .of),
    projectIndexMethod(.references, label: .to),
    projectIndexMethod(.definitions, label: .of),
    projectIndexMethod(.occurrences, label: .of),
    method(
      .contains,
      on: [.symbolRoles],
      arguments: .exact([.init(nil, .exact(.staticMember([.symbolRole])))]),
      result: .fixed(.boolean)
    ),
  ]

  private static func codebaseSelection(
    _ name: Member,
    family: DeclarationFamily
  ) -> RuntimeMemberAPI {
    property(
      name,
      on: [.codebase],
      result: .fixed(.selection(family)),
      canSuspend: true
    )
  }

  private static func indexArguments(
    leading: [RuntimeCallParameter]
  ) -> RuntimeCallArguments {
    .indexQuery(
      leading: leading,
      optional: [
        .init(.modules, .exact(.optional(.array(.string)))),
        .init(.unitOutputFiles, .exact(.optional(.array(.string)))),
      ]
    )
  }

  private static func codebasePackageMethod(
    _ name: Member,
    result: ModelType
  ) -> RuntimeMemberAPI {
    method(
      name,
      on: [.codebase],
      arguments: .optional(
        .init(.ignoring, .exact(.array(.string)))
      ),
      result: .fixed(.model(result)),
      canSuspend: true
    )
  }

  private static func codebaseIndexMethod(
    _ name: Member,
    label: ArgumentLabel
  ) -> RuntimeMemberAPI {
    method(
      name,
      on: [.codebase],
      arguments: indexArguments(
        leading: [.init(label, .exact(.string))]
      ),
      result: .fixed(.array(.model(.indexReference))),
      canSuspend: true
    )
  }

  private static func projectIndexMethod(
    _ name: Member,
    label: ArgumentLabel
  ) -> RuntimeMemberAPI {
    method(
      name,
      on: [.projectIndex],
      arguments: .exact([.init(label, .exact(.string))]),
      result: .fixed(.array(.model(.indexReference))),
      canSuspend: true
    )
  }
}
