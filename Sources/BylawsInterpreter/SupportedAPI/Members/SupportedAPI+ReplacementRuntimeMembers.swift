extension SupportedAPI {
  static let replacementRuntimeMembers: [RuntimeMemberAPI] = [
    property(
      .replacement,
      on: [.sourceScope],
      result: .fixed(.sourceReplacement)
    ),
    property(
      .ifExpression,
      on: [.model(.sourceNode)],
      result: .fixed(.optional(.model(.sourceIfExpression)))
    ),
    property(
      .body,
      on: [.model(.sourceIfExpression)],
      result: .fixed(.model(.sourceNode))
    ),
    property(
      .elseBody,
      on: [.model(.sourceIfExpression)],
      result: .fixed(.optional(.model(.sourceNode)))
    ),
    property(
      .summary,
      on: [.model(.sourceIfExpression)],
      result: .fixed(.string)
    ),
    property(
      .location,
      on: [.model(.sourceIfExpression)],
      result: .fixed(.model(.declarationLocation))
    ),
    method(
      .unwrapped,
      on: [.sourceSlice, .model(.sourceNode)],
      arguments: .optional(.init(
        .containingOnly,
        .exact(.optional(.staticMember([.sourceNodeKind])))
      )),
      result: .fixed(.sourceCorrection),
      canThrow: true
    ),
  ]
}
