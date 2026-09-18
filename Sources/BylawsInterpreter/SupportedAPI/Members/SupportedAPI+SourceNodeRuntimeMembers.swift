extension SupportedAPI {
  static let sourceNodeRuntimeMembers: [RuntimeMemberAPI] = [
    property(
      .kind,
      on: [.model(.sourceNode)],
      result: .fixed(.staticMember([.sourceNodeKind]))
    ),
    property(.text, on: [.model(.sourceNode)], result: .fixed(.string)),
    property(
      .description,
      on: [.model(.sourceNode)],
      result: .fixed(.string)
    ),
    property(
      .call,
      on: [.model(.sourceNode)],
      result: .fixed(.optional(.model(.functionCall)))
    ),
    property(
      .expression,
      on: [.model(.sourceNode)],
      result: .fixed(.optional(.model(.sourceExpression)))
    ),
    property(
      .children,
      on: [.model(.sourceNode)],
      result: .fixed(.array(.model(.sourceNode)))
    ),
    property(
      .descendants,
      on: [.model(.sourceNode)],
      result: .fixed(.array(.model(.sourceNode)))
    ),
    property(
      .parent,
      on: [.model(.sourceNode)],
      result: .fixed(.optional(.model(.sourceNode)))
    ),
    property(
      .ancestors,
      on: [.model(.sourceNode)],
      result: .fixed(.array(.model(.sourceNode)))
    ),
    property(
      .location,
      on: [.model(.sourceNode)],
      result: .fixed(.model(.declarationLocation))
    ),
  ]
}
