extension FunctionCall {
  /// The call's arguments and their insertion position when the list is empty.
  public var argumentList: SourceList<Argument> {
    get throws { try SourceList(arguments, owner: source, kind: .arguments) }
  }
}

extension Attributed where Self: SourceProviding {
  /// The declaration's attributes, including the position for its first attribute.
  public var attributeList: SourceList<Attribute> {
    get throws { try SourceList(attributes, owner: source, kind: .attributes) }
  }

  /// The declaration's modifiers as captured source, including an empty list.
  public var modifierList: SourceList<SourceSlice> {
    get throws {
      let owner = try source
      let list = try SourceListContext(owner: owner, kind: .modifiers).resolve()
      return try SourceList(list.slices(), owner: owner, kind: .modifiers)
    }
  }
}

extension SourceNode {
  /// The declaration's modifiers and the position for its first modifier.
  public var modifierList: SourceList<SourceNode> {
    get throws { try SourceList(modifiers, owner: source, kind: .modifiers) }
  }

  /// The declaration's members and the position for its first member.
  public var memberList: SourceList<SourceNode> {
    get throws { try SourceList(members, owner: source, kind: .members) }
  }

  /// The block's statements and the position for its first statement.
  public var statementList: SourceList<SourceNode> {
    get throws { try SourceList(statements, owner: source, kind: .statements) }
  }
}
