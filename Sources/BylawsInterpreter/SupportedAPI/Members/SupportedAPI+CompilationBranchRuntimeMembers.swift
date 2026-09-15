extension SupportedAPI {
  static let compilationBranchRuntimeMembers: [RuntimeMemberAPI] = [
    property(
      .compilationBranches,
      on: [
        .model(.sourceFile),
        .model(.sourceExpression),
        .model(.sourceAssignment),
        .model(.variableBinding),
      ],
      result: .fixed(.array(.model(.compilationBranch)))
    ),
    property(.name, on: [.model(.compilationBranch)], result: .fixed(.string)),
    property(
      .location, on: [.model(.compilationBranch)],
      result: .fixed(.model(.declarationLocation))
    ),
    property(
      .condition, on: [.model(.compilationBranch)],
      result: .fixed(.optional(.string))
    ),
    property(
      .precedingConditions, on: [.model(.compilationBranch)],
      result: .fixed(.array(.string))
    ),
    method(
      .contains, on: [.model(.compilationBranch)],
      arguments: .exact([.init(nil, .exact(.model(.declarationLocation)))]),
      result: .fixed(.boolean)
    ),
  ]
}
