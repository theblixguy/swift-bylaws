extension SupportedAPI {
  static let lexicalRuntimeMembers: [RuntimeMemberAPI] = [
    property(
      .source,
      on: [.model(.sourceToken), .model(.sourceTrivia)],
      result: .fixed(.sourceSlice)
    ),
    property(
      .tokens,
      on: Set(sourceProvidingModels.map(RuntimeReceiver.model))
        .union([.sourceSlice]),
      result: .fixed(.array(.model(.sourceToken))), canThrow: true
    ),
    property(
      .trivia,
      on: Set(sourceProvidingModels.map(RuntimeReceiver.model))
        .union([.sourceSlice]),
      result: .fixed(.array(.model(.sourceTrivia))), canThrow: true
    ),
    property(
      .text,
      on: [.model(.sourceToken), .model(.sourceTrivia)],
      result: .fixed(.string)
    ),
    property(
      .kind,
      on: [.model(.sourceToken)],
      result: .fixed(.staticMember([.sourceTokenKind]))
    ),
    property(
      .kind,
      on: [.model(.sourceTrivia)],
      result: .fixed(.staticMember([.sourceTriviaKind]))
    ),
    property(
      .previous,
      on: [.model(.sourceToken)],
      result: .fixed(.optional(.model(.sourceToken)))
    ),
    property(
      .next,
      on: [.model(.sourceToken)],
      result: .fixed(.optional(.model(.sourceToken)))
    ),
    property(
      .leadingTrivia,
      on: [.model(.sourceToken)],
      result: .fixed(.array(.model(.sourceTrivia)))
    ),
    property(
      .trailingTrivia,
      on: [.model(.sourceToken)],
      result: .fixed(.array(.model(.sourceTrivia)))
    ),
    property(.isComment, on: [.model(.sourceTrivia)], result: .fixed(.boolean)),
    method(
      .contains,
      on: [.model(.sourceNode)],
      arguments: .exact([.init(
        nil,
        .exact(.staticMember([.sourceNodeKind]))
      )]),
      result: .fixed(.boolean)
    ),
    property(
      .elements,
      on: [.model(.sourceNode)],
      result: .fixed(.array(.model(.sourceNode)))
    ),
  ]
}
