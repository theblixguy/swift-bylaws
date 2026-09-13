import SwiftSyntax

extension RuntimeEvaluator {
  func syntaxClassMember(
    _ name: SupportedAPI.Member,
    _ value: ClassDeclSyntax
  ) -> RuntimeValue? {
    name == .memberBlock
      ? .model(.syntaxMemberBlock(value.memberBlock)) : nil
  }

  func syntaxMemberBlockMember(
    _ name: SupportedAPI.Member,
    _ value: MemberBlockSyntax
  ) -> RuntimeValue? {
    name == .members ? .array(value.members.map { _ in .void }) : nil
  }

  func syntaxTokenMember(
    _ name: SupportedAPI.Member,
    _ value: TokenSyntax
  ) -> RuntimeValue? {
    switch name {
    case .leadingTrivia:
      .array(value.leadingTrivia.map { .model(.syntaxTriviaPiece($0)) })
    case .trailingTrivia:
      .array(value.trailingTrivia.map { .model(.syntaxTriviaPiece($0)) })
    case .text: .string(value.text)
    default: nil
    }
  }

  func syntaxTriviaMember(
    _ name: SupportedAPI.Member,
    _ value: TriviaPiece
  ) -> RuntimeValue? {
    switch name {
    case .isComment: .boolean(value.isComment)
    case .description: .string(Trivia(pieces: [value]).description)
    default: nil
    }
  }
}
