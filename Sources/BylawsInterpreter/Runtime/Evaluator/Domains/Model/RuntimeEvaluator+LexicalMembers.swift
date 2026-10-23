import BylawsSemantics

extension RuntimeEvaluator {
  func sourceTokenMember(
    _ name: SupportedAPI.Member,
    _ token: SourceToken
  ) -> RuntimeValue? {
    switch name {
    case .text: .string(token.text)
    case .kind: RuntimeValue.member(naming: token.kind)
    case .previous: .optional(token.previous.map { .model(.sourceToken($0)) })
    case .next: .optional(token.next.map { .model(.sourceToken($0)) })
    case .leadingTrivia: .array(token.leadingTrivia
        .map { .model(.sourceTrivia($0)) })
    case .trailingTrivia: .array(token.trailingTrivia
        .map { .model(.sourceTrivia($0)) })
    default: nil
    }
  }

  func sourceTriviaMember(
    _ name: SupportedAPI.Member,
    _ trivia: SourceTrivia
  ) -> RuntimeValue? {
    switch name {
    case .text: .string(trivia.text)
    case .kind: RuntimeValue.member(naming: trivia.kind)
    case .isComment: .boolean(trivia.isComment)
    default: nil
    }
  }
}
