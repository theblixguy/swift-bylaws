import BylawsSyntax

final class PropertyGroupingRewriter: SyntaxRewriter {
  private enum Group: CaseIterable {
    case environmentKeyPath, environmentType, state, privateConstant, constant

    func startsSection(after previous: Self) -> Bool {
      switch (previous, self) {
      case (.environmentKeyPath, .environmentType),
           (.privateConstant, .constant): false
      default: self != previous
      }
    }
  }

  override func visit(
    _ node: MemberBlockItemListSyntax
  ) -> MemberBlockItemListSyntax {
    var members: [MemberBlockItemSyntax] = []
    var properties: [(member: MemberBlockItemSyntax, group: Group)] = []
    for member in super.visit(node) {
      if let group = group(of: member) {
        properties.append((member, group))
      } else {
        members.append(contentsOf: grouped(properties))
        properties.removeAll(keepingCapacity: true)
        members.append(member)
      }
    }
    members.append(contentsOf: grouped(properties))
    return MemberBlockItemListSyntax(members)
  }

  private func group(of member: MemberBlockItemSyntax) -> Group? {
    guard member.semicolon == nil,
          let property = member.decl.as(VariableDeclSyntax.self),
          property.bindings.count == 1,
          property.bindings.first?.accessorBlock == nil
    else { return nil }
    let isPrivate = property.modifiers.count == 1
      && property.modifiers.first?.name.tokenKind == .keyword(.private)
      && property.modifiers.first?.detail == nil
    guard property.modifiers.isEmpty || isPrivate else { return nil }
    if property.attributes.isEmpty {
      guard property.bindingSpecifier.tokenKind == .keyword(.let)
      else { return nil }
      return isPrivate ? .privateConstant : .constant
    }
    guard property.bindingSpecifier.tokenKind == .keyword(.var),
          property.attributes.count == 1,
          let attribute = property.attributes.first?.as(AttributeSyntax.self)
    else { return nil }
    let name = attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text
      ?? attribute.attributeName.as(MemberTypeSyntax.self)?.name.text
    if name == "State" { return .state }
    guard name == "Environment",
          case let .argumentList(arguments) = attribute.arguments,
          arguments.count == 1,
          let argument = arguments.first,
          argument.label == nil
    else { return nil }
    if argument.expression.is(KeyPathExprSyntax.self) {
      return .environmentKeyPath
    }
    if let type = argument.expression.as(MemberAccessExprSyntax.self),
       type.base != nil, type.declName.baseName.text == "self"
    {
      return .environmentType
    }
    return nil
  }

  private func grouped(
    _ properties: [(member: MemberBlockItemSyntax, group: Group)]
  ) -> [MemberBlockItemSyntax] {
    guard let first = properties.first else { return [] }
    let prefix = first.member.leadingTrivia.prefix(while: \.isWhitespace)
    var members: [MemberBlockItemSyntax] = []
    var previous: Group?
    for group in Group.allCases {
      for property in properties where property.group == group {
        var member = property.member
        let trivia = member.leadingTrivia
        let whitespace = trivia.prefix(while: \.isWhitespace)
        let attachedTrivia = trivia.dropFirst(whitespace.count)
        if let previous {
          let count = group.startsSection(after: previous) ? 2 : 1
          let indentation = whitespace.reversed()
            .prefix(while: \.isSpaceOrTab).reversed()
          member.leadingTrivia = newline(count, matching: prefix)
            + Trivia(pieces: indentation) + Trivia(pieces: attachedTrivia)
        } else {
          member.leadingTrivia = Trivia(pieces: prefix)
            + Trivia(pieces: attachedTrivia)
        }
        members.append(member)
        previous = group
      }
    }
    return members
  }

  private func newline(
    _ count: Int, matching whitespace: Trivia.SubSequence
  ) -> Trivia {
    switch whitespace.first(where: \.isNewline) {
    case .carriageReturnLineFeeds: .carriageReturnLineFeeds(count)
    case .carriageReturns: .carriageReturns(count)
    default: .newlines(count)
    }
  }
}
