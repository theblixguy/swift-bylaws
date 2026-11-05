extension SupportedAPI {
  static let sourceListRuntimeMembers: [RuntimeMemberAPI] = [
    property(
      .argumentList, on: [.model(.functionCall)],
      result: .fixed(.sourceList(.model(.callArgument))), canThrow: true
    ),
    property(
      .attributeList, on: attributedReceivers.union([.model(.sourceNode)]),
      result: .fixed(.sourceList(.model(.attribute))), canThrow: true
    ),
    property(
      .modifierList, on: attributedReceivers,
      result: .fixed(.sourceList(.sourceSlice)), canThrow: true
    ),
    property(
      .modifierList, on: [.model(.sourceNode)],
      result: .fixed(.sourceList(.model(.sourceNode))), canThrow: true
    ),
    property(
      .memberList, on: [.model(.sourceNode)],
      result: .fixed(.sourceList(.model(.sourceNode))), canThrow: true
    ),
    property(
      .statementList, on: [.model(.sourceNode)],
      result: .fixed(.sourceList(.model(.sourceNode))), canThrow: true
    ),
    property(
      .source, on: [.sourceList], result: .fixed(.sourceSlice), canThrow: true
    ),
    method(
      .inserting, on: [.sourceList],
      arguments: .alternatives([
        [.init(nil, .exact(.string))],
        [
          .init(nil, .exact(.string)),
          .init(.at, .exact(.staticMember([.sourceListPosition]))),
        ],
      ]),
      result: .fixed(.sourceCorrection), canThrow: true
    ),
    method(
      .removing, on: [.sourceList],
      arguments: .exact([.init(nil, .collectionElement)]),
      result: .fixed(.sourceCorrection), canThrow: true
    ),
    method(
      .removal,
      on: Set(sourceProvidingModels.map(RuntimeReceiver.model))
        .union([.sourceSlice]),
      arguments: .exact([]), result: .fixed(.sourceCorrection), canThrow: true
    ),
  ]
}
