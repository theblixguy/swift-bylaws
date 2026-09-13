extension SupportedAPI {
  static let syntaxRuntimeMembers: [RuntimeMemberAPI] = [
    property(
      .memberBlock,
      on: [.model(.syntaxClass)],
      result: .fixed(.model(.syntaxMemberBlock))
    ),
    property(
      .members,
      on: [.model(.syntaxMemberBlock)],
      result: .fixed(.array(.void))
    ),
    property(
      .leadingTrivia,
      on: [.model(.syntaxToken)],
      result: .fixed(.array(.model(.syntaxTriviaPiece)))
    ),
    property(
      .trailingTrivia,
      on: [.model(.syntaxToken)],
      result: .fixed(.array(.model(.syntaxTriviaPiece)))
    ),
    property(.text, on: [.model(.syntaxToken)], result: .fixed(.string)),
    property(
      .isComment,
      on: [.model(.syntaxTriviaPiece)],
      result: .fixed(.boolean)
    ),
    property(
      .description,
      on: [.model(.syntaxTriviaPiece)],
      result: .fixed(.string)
    ),
  ]

  static let typeRuntimeMembers: [RuntimeMemberAPI] = [
    property(
      .selfType,
      on: Set(runtimeTypeNames.map(RuntimeReceiver.staticType)),
      result: .receiver
    ),
    property(
      .kindType,
      on: [.staticType(ModelType.indexSymbol.rawValue)],
      result: .fixed(.staticType(StaticMemberType.indexSymbolKind.rawValue))
    ),
  ]
}
