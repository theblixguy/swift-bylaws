extension SupportedAPI {
  static let bodyRuntimeMembers: [RuntimeMemberAPI] = [
    property(
      .assignments, on: [.model(.sourceFile)],
      result: .fixed(.array(.model(.sourceAssignment)))
    ),
    property(
      .variableBindings, on: [.model(.sourceFile)],
      result: .fixed(.array(.model(.variableBinding)))
    ),
    property(
      .target, on: [.model(.sourceAssignment)],
      result: .fixed(.model(.sourceExpression))
    ),
    property(
      .value, on: [.model(.sourceAssignment)],
      result: .fixed(.model(.sourceExpression))
    ),
    property(
      .operatorName, on: [.model(.sourceAssignment)], result: .fixed(.string)
    ),
    property(
      .initialValue, on: [.model(.variableBinding)],
      result: .fixed(.optional(.model(.sourceExpression)))
    ),
    property(
      .isMutable,
      on: [.model(.variableBinding)],
      result: .fixed(.boolean)
    ),
    property(
      .enclosingDeclarations,
      on: [
        .model(.sourceExpression),
        .model(.sourceAssignment),
        .model(.variableBinding),
      ],
      result: .fixed(.array(.model(.enclosingDeclaration)))
    ),
    property(
      .name,
      on: [
        .model(.sourceAssignment),
        .model(.variableBinding),
        .model(.enclosingDeclaration),
      ],
      result: .fixed(.string)
    ),
    property(
      .location,
      on: [
        .model(.sourceAssignment),
        .model(.variableBinding),
        .model(.enclosingDeclaration),
      ],
      result: .fixed(.model(.declarationLocation))
    ),
  ]
}
