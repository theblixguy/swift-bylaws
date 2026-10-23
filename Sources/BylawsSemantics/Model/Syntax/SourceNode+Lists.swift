import BylawsSyntax

extension SourceNode {
  /// The direct elements of a represented syntax list, in source order.
  ///
  /// Returns an empty array for a node that is not a represented list.
  /// Elements without a more specific kind use ``Kind/syntaxElement``.
  /// An element's `source` and `text` include its trailing comma, when present.
  /// Nested layout edits must leave that separator outside their source range.
  /// - Complexity: O(n), where n is the number of elements.
  public var elements: [Self] {
    switch kind {
    case .conditionList, .genericParameterList, .genericArgumentList,
         .genericRequirementList, .inheritedTypeList, .expressionList,
         .tupleTypeElementList, .tuplePatternElementList, .closureParameterList,
         .closureShorthandParameterList, .closureCaptureList,
         .enumCaseParameterList, .primaryAssociatedTypeList, .accessorList,
         .switchCaseList, .switchCaseItemList:
      syntax.children(viewMode: .sourceAccurate).map {
        Self($0, context: context, kind: Kind($0) ?? .syntaxElement)
      }
    default: []
    }
  }

  /// The direct members of a declaration, in source order.
  ///
  /// Returns an empty array for a node without a member block.
  /// - Complexity: O(n), where n is the number of members.
  public var members: [Self] {
    guard let block = syntax.children(viewMode: .sourceAccurate)
      .first(where: { $0.is(MemberBlockSyntax.self) })?
      .as(MemberBlockSyntax.self)
    else { return [] }
    return block.members.compactMap { model(Syntax($0.decl)) }
  }

  /// The direct statements of a code block, closure or source file.
  ///
  /// - Complexity: O(n), where n is the number of statements.
  public var statements: [Self] {
    let statements: CodeBlockItemListSyntax? = if let block = syntax
      .as(CodeBlockSyntax.self)
    {
      block.statements
    } else if let closure = syntax.as(ClosureExprSyntax.self) {
      closure.statements
    } else {
      syntax.as(SourceFileSyntax.self)?.statements
    }
    return statements?.compactMap { item in
      let syntax = Syntax(item.item)
      if let kind = Kind(syntax) {
        return Self(syntax, context: context, kind: kind)
      }
      return syntax.is(ExprSyntax.self)
        ? Self(syntax, context: context, kind: .expressionStatement) : nil
    } ?? []
  }

  /// The declaration modifiers, in source order.
  ///
  /// - Complexity: O(n), where n is the number of modifiers.
  public var modifiers: [Self] {
    guard let list = syntax.children(viewMode: .sourceAccurate)
      .first(where: { $0.is(DeclModifierListSyntax.self) })?
      .as(DeclModifierListSyntax.self)
    else { return [] }
    return list.compactMap { model(Syntax($0)) }
  }

  /// The function, initialiser or subscript parameters, in source order.
  ///
  /// - Complexity: O(n), where n is the number of parameters.
  public var parameters: [Self] {
    let clause: FunctionParameterClauseSyntax? = if let function = syntax
      .as(FunctionDeclSyntax.self)
    {
      function.signature.parameterClause
    } else if let initializer = syntax.as(InitializerDeclSyntax.self) {
      initializer.signature.parameterClause
    } else {
      syntax.as(SubscriptDeclSyntax.self)?.parameterClause
    }
    return clause?.parameters.compactMap { model(Syntax($0)) } ?? []
  }

  /// The direct case declarations of an enum, or the elements of one case declaration.
  ///
  /// - Complexity: O(n), where n is the number of members or case elements.
  public var cases: [Self] {
    if let declaration = syntax.as(EnumCaseDeclSyntax.self) {
      return declaration.elements.compactMap { model(Syntax($0)) }
    }
    guard syntax.is(EnumDeclSyntax.self) else { return [] }
    return members.filter { $0.kind == .enumCaseDeclaration }
  }

  /// The declaration's attributes, in source order.
  ///
  /// - Complexity: O(n), where n is the number of attributes.
  public var attributes: [Attribute] {
    guard let list = syntax.children(viewMode: .sourceAccurate)
      .first(where: { $0.is(AttributeListSyntax.self) })?
      .as(AttributeListSyntax.self)
    else { return [] }
    return ModifierReader.attributes(
      list, reader: SyntaxReader(
        path: context.origin.filePath,
        text: context.source
      )
    )
  }

  /// The single global or member property declared by this node.
  ///
  /// Returns `nil` for declarations inside function bodies, declarations with
  /// several bindings and other syntax forms. The property retains its enclosing declaration,
  /// visibility and captured source.
  public var property: Property? {
    guard let declaration = syntax.as(VariableDeclSyntax.self),
          declaration.bindings.count == 1,
          let identifier = declaration.bindings.first?.pattern
            .as(IdentifierPatternSyntax.self)?.identifier,
          let originOffset = context.origin.utf8Offset
    else { return nil }
    let offset = originOffset + identifier.positionAfterSkippingLeadingTrivia
      .utf8Offset
    return context.propertiesByOffset[offset]
  }

  /// The declared identifier or modifier name, or `nil` for an unnamed node.
  public var name: String? {
    switch syntax.as(SyntaxEnum.self) {
    case let .functionDecl(node): node.name.text
    case let .classDecl(node): node.name.text
    case let .structDecl(node): node.name.text
    case let .actorDecl(node): node.name.text
    case let .enumDecl(node): node.name.text
    case let .protocolDecl(node): node.name.text
    case let .typeAliasDecl(node): node.name.text
    case let .enumCaseElement(node): node.name.text
    case let .declModifier(node): node.name.text
    case let .functionParameter(node): (node.secondName ?? node.firstName).text
    case let .enumCaseDecl(node): node.elements.count == 1 ? node.elements
      .first?.name.text : nil
    case let .variableDecl(node):
      node.bindings.count == 1
        ? node.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?
        .identifier.text : nil
    default: nil
    }
  }

  private func model(_ syntax: Syntax) -> Self? {
    Kind(syntax).map { Self(syntax, context: context, kind: $0) }
  }
}

extension SourceNode: Attributed {}
