import SwiftSyntax

final class DeclarationVisitor: SyntaxVisitor {
  private let reader: SyntaxReader
  private var typeNameStack: [String] = []
  private var memberVisibilityStack: [Visibility] = []
  private var enumIndexStack: [Int] = []

  private(set) var imports: [Import] = []
  private(set) var classes: [Class] = []
  private(set) var actors: [Actor] = []
  private(set) var structs: [Struct] = []
  private(set) var enums: [Enum] = []
  private(set) var protocols: [ProtocolDeclaration] = []
  private(set) var extensions: [Extension] = []
  private(set) var functions: [Function] = []
  private(set) var properties: [Property] = []
  private(set) var initializers: [Initializer] = []
  private(set) var typealiases: [Typealias] = []
  private(set) var macroExpansions: [FunctionCall] = []

  var sourceBuffer: SourceBuffer { reader.text.buffer }

  init(path: String, text: SourceText) {
    reader = SyntaxReader(path: path, text: text)
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    let fields = nominalTypeFields(of: node)
    classes.append(
      Class(
        storage: nominalTypeStorage(
          fields,
          genericClause: node.genericParameterClause
        ),
        isFinal: fields.modifiers.isFinal
      )
    )
    enterType(name: fields.name, visibility: .internal)
    return .visitChildren
  }

  override func visitPost(_ node: ClassDeclSyntax) {
    leaveType()
  }

  override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
    let fields = nominalTypeFields(of: node)
    actors.append(
      Actor(
        storage: nominalTypeStorage(
          fields,
          genericClause: node.genericParameterClause
        )
      )
    )
    enterType(name: fields.name, visibility: .internal)
    return .visitChildren
  }

  override func visitPost(_ node: ActorDeclSyntax) {
    leaveType()
  }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    let fields = nominalTypeFields(of: node)
    structs.append(
      Struct(
        storage: nominalTypeStorage(
          fields,
          genericClause: node.genericParameterClause
        )
      )
    )
    enterType(name: fields.name, visibility: .internal)
    return .visitChildren
  }

  override func visitPost(_ node: StructDeclSyntax) {
    leaveType()
  }

  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    let fields = nominalTypeFields(of: node)
    enums.append(
      Enum(
        storage: nominalTypeStorage(
          fields,
          genericClause: node.genericParameterClause
        ),
        isIndirect: fields.modifiers.isIndirect
      )
    )
    enumIndexStack.append(enums.index(before: enums.endIndex))
    enterType(name: fields.name, visibility: .internal)
    return .visitChildren
  }

  override func visitPost(_ node: EnumDeclSyntax) {
    enumIndexStack.removeLast()
    leaveType()
  }

  private func nominalTypeStorage(
    _ fields: NominalTypeFields,
    genericClause: GenericParameterClauseSyntax?
  ) -> NominalTypeStorage {
    NominalTypeStorage(
      name: fields.name,
      inheritedTypes: fields.inheritedTypes,
      genericParameters: reader.genericParameters(of: genericClause),
      source: sourceBuffer,
      sourceRange: fields.sourceRange,
      isNonisolated: fields.modifiers.isNonisolated,
      visibility: fields.modifiers.visibility,
      attributes: fields.attributes,
      enclosingTypeName: enclosingTypeName,
      documentation: fields.documentation,
      location: fields.location
    )
  }

  private func nominalTypeFields(
    of node: some DeclGroupSyntax & NamedDeclSyntax
  ) -> NominalTypeFields {
    NominalTypeFields(
      name: node.name.text,
      inheritedTypes: reader.inheritedTypeNames(node.inheritanceClause),
      sourceRange: reader.trimmedRange(of: node),
      modifiers: ModifierReader(
        node.modifiers,
        defaultVisibility: memberVisibility
      ),
      attributes: ModifierReader.attributes(node.attributes),
      documentation: reader.documentation(of: node),
      location: reader.location(of: node.name)
    )
  }

  override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
    let fields = nominalTypeFields(of: node)
    let modifiers = fields.modifiers
    let name = fields.name
    let qualified = enclosingTypeName.map { "\($0).\(name)" } ?? name
    var requiredFunctions: [Function] = []
    var requiredProperties: [Property] = []
    for member in node.memberBlock.members {
      if let requirement = member.decl.as(FunctionDeclSyntax.self) {
        requiredFunctions
          .append(
            function(
              from: requirement,
              enclosing: qualified,
              defaultVisibility: modifiers.visibility
            )
          )
      } else if let requirement = member.decl.as(VariableDeclSyntax.self) {
        requiredProperties
          += properties(
            from: requirement,
            enclosing: qualified,
            defaultVisibility: modifiers.visibility
          )
      }
    }
    protocols.append(
      ProtocolDeclaration(
        name: name,
        inheritedTypes: fields.inheritedTypes,
        source: sourceBuffer,
        sourceRange: fields.sourceRange,
        isNonisolated: modifiers.isNonisolated,
        visibility: modifiers.visibility,
        attributes: fields.attributes,
        requiredFunctions: requiredFunctions,
        requiredProperties: requiredProperties,
        documentation: fields.documentation,
        location: fields.location
      )
    )
    return .skipChildren
  }

  override func visit(_ node: ExtensionDeclSyntax)
    -> SyntaxVisitorContinueKind
  {
    let extendedTypeName = node.extendedType.trimmedDescription
    let modifiers = ModifierReader(
      node.modifiers,
      defaultVisibility: memberVisibility
    )
    extensions.append(
      Extension(
        extendedTypeName: extendedTypeName,
        inheritedTypes: reader.inheritedTypeNames(node.inheritanceClause),
        visibility: modifiers.visibility,
        attributes: ModifierReader.attributes(node.attributes),
        location: reader.location(of: node.extendedType)
      )
    )
    enterType(name: extendedTypeName, visibility: modifiers.visibility)
    return .visitChildren
  }

  override func visitPost(_ node: ExtensionDeclSyntax) {
    leaveType()
  }

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    functions.append(function(from: node, enclosing: enclosingTypeName))
    return .skipChildren
  }

  override func visit(_ node: InitializerDeclSyntax)
    -> SyntaxVisitorContinueKind
  {
    let modifiers = ModifierReader(
      node.modifiers,
      defaultVisibility: memberVisibility
    )
    let metrics = reader.bodyMetrics(of: node.body)
    initializers.append(
      Initializer(
        parameters: reader.parameters(of: node.signature.parameterClause),
        isFailable: node.optionalMark != nil,
        isConvenience: modifiers.isConvenience,
        isAsync: node.signature.effectSpecifiers?.asyncSpecifier != nil,
        isThrowing: node.signature.effectSpecifiers?.throwsClause != nil,
        isNonisolated: modifiers.isNonisolated,
        visibility: modifiers.visibility,
        attributes: ModifierReader.attributes(node.attributes),
        enclosingTypeName: enclosingTypeName,
        calls: reader.calls(in: node.body),
        awaitCount: metrics.awaitCount,
        cyclomaticComplexity: metrics.cyclomaticComplexity,
        documentation: reader.documentation(of: node),
        location: reader.location(of: node.initKeyword)
      )
    )
    return .skipChildren
  }

  override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
    properties += properties(from: node, enclosing: enclosingTypeName)
    return .skipChildren
  }

  override func visit(_ node: TypeAliasDeclSyntax)
    -> SyntaxVisitorContinueKind
  {
    let modifiers = ModifierReader(
      node.modifiers,
      defaultVisibility: memberVisibility
    )
    typealiases.append(
      Typealias(
        name: node.name.text,
        aliasedTypeName: node.initializer.value.trimmedDescription,
        visibility: modifiers.visibility,
        attributes: ModifierReader.attributes(node.attributes),
        enclosingTypeName: enclosingTypeName,
        documentation: reader.documentation(of: node),
        location: reader.location(of: node.name)
      )
    )
    return .skipChildren
  }

  override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
    guard let enumIndex = enumIndexStack.last else { return .skipChildren }
    let modifiers = ModifierReader(node.modifiers)
    for element in node.elements {
      enums[enumIndex].cases.append(
        EnumCase(
          name: element.name.text,
          isIndirect: modifiers.isIndirect,
          rawValue: element.rawValue?.value.trimmedDescription,
          enclosingTypeName: enclosingTypeName,
          documentation: reader.documentation(of: node),
          location: reader.location(of: element.name)
        )
      )
    }
    return .skipChildren
  }

  override func visit(_ node: DeinitializerDeclSyntax)
    -> SyntaxVisitorContinueKind
  {
    .skipChildren
  }

  override func visit(_ node: SubscriptDeclSyntax)
    -> SyntaxVisitorContinueKind
  {
    .skipChildren
  }

  // Declarations inside a macro are not members of the enclosing type.
  override func visit(_ node: MacroExpansionDeclSyntax)
    -> SyntaxVisitorContinueKind
  {
    recordMacro(named: node.macroName.text, arguments: node.arguments, at: node)
    return .skipChildren
  }

  override func visit(_ node: MacroExpansionExprSyntax)
    -> SyntaxVisitorContinueKind
  {
    recordMacro(named: node.macroName.text, arguments: node.arguments, at: node)
    return .skipChildren
  }

  override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
    let modifiers = ModifierReader(node.modifiers)
    imports.append(
      Import(
        name: node.path.trimmedDescription,
        kind: node.importKindSpecifier
          .flatMap { ImportKind(rawValue: $0.text) },
        visibility: modifiers.visibility,
        attributes: ModifierReader.attributes(node.attributes),
        location: reader.location(of: node.path)
      )
    )
    return .skipChildren
  }

  private func function(
    from node: FunctionDeclSyntax,
    enclosing: String?,
    defaultVisibility: Visibility? = nil
  ) -> Function {
    let modifiers = ModifierReader(
      node.modifiers,
      defaultVisibility: defaultVisibility ?? memberVisibility
    )
    let effects = node.signature.effectSpecifiers
    let metrics = reader.bodyMetrics(of: node.body)
    return Function(
      name: node.name.text,
      source: sourceBuffer,
      parameters: reader.parameters(of: node.signature.parameterClause),
      returnType: node.signature.returnClause.map { TypeReference($0.type) },
      isStatic: modifiers.isStatic,
      isOverride: modifiers.isOverride,
      isMutating: modifiers.isMutating,
      isDynamic: modifiers.isDynamic,
      isAsync: effects?.asyncSpecifier != nil,
      isThrowing: effects?.throwsClause != nil,
      isNonisolated: modifiers.isNonisolated,
      genericParameters: reader
        .genericParameters(of: node.genericParameterClause),
      visibility: modifiers.visibility,
      attributes: ModifierReader.attributes(node.attributes),
      enclosingTypeName: enclosing,
      calls: reader.calls(in: node.body),
      bodyLineCount: reader.lineCount(of: node.body),
      awaitCount: metrics.awaitCount,
      cyclomaticComplexity: metrics.cyclomaticComplexity,
      sourceRange: reader.trimmedRange(of: node),
      documentation: reader.documentation(of: node),
      location: reader.location(of: node.name)
    )
  }

  private func properties(
    from node: VariableDeclSyntax,
    enclosing: String?,
    defaultVisibility: Visibility? = nil
  ) -> [Property] {
    let modifiers = ModifierReader(
      node.modifiers,
      defaultVisibility: defaultVisibility ?? memberVisibility
    )
    let attributes = ModifierReader.attributes(node.attributes)
    let isConstant = node.bindingSpecifier.tokenKind == .keyword(.let)
    var inheritedType: TypeSyntax?
    let bindings = node.bindings.reversed().map { binding in
      if let type = binding.typeAnnotation?.type {
        inheritedType = type
      } else if binding.initializer != nil || binding.accessorBlock != nil {
        inheritedType = nil
      }
      return (binding, inheritedType)
    }.reversed()
    return bindings.compactMap { binding, inheritedType in
      guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self)
      else { return nil }
      return Property(
        name: pattern.identifier.text,
        type: inheritedType.map(TypeReference.init),
        isConstant: isConstant,
        isStatic: modifiers.isStatic,
        ownership: modifiers.ownership,
        isLazy: modifiers.isLazy,
        isDynamic: modifiers.isDynamic,
        isNonisolated: modifiers.isNonisolated,
        isNonisolatedUnsafe: modifiers.isNonisolatedUnsafe,
        visibility: modifiers.visibility,
        attributes: attributes,
        enclosingTypeName: enclosing,
        calls: reader.calls(in: binding.initializer?.value)
          + reader.calls(in: binding.accessorBlock),
        documentation: reader.documentation(of: node),
        location: reader.location(of: pattern.identifier)
      )
    }
  }

  private func recordMacro(
    named name: String,
    arguments: LabeledExprListSyntax,
    at node: some SyntaxProtocol
  ) {
    macroExpansions.append(
      FunctionCall(
        calledExpression: "#\(name)",
        arguments: arguments.map {
          FunctionCall.Argument(
            label: $0.label?.text,
            text: reader.trimmedSourceText(of: $0.expression)
          )
        },
        location: reader.location(of: node)
      )
    )
  }

  private func enterType(name: String, visibility: Visibility) {
    typeNameStack.append(name)
    memberVisibilityStack.append(visibility)
  }

  private func leaveType() {
    typeNameStack.removeLast()
    memberVisibilityStack.removeLast()
  }

  private var enclosingTypeName: String? {
    typeNameStack.isEmpty ? nil : typeNameStack.joined(separator: ".")
  }

  private var memberVisibility: Visibility {
    memberVisibilityStack.last ?? .internal
  }
}

private struct NominalTypeFields {
  let name: String
  let inheritedTypes: [String]
  let sourceRange: Range<Int>
  let modifiers: ModifierReader
  let attributes: [Attribute]
  let documentation: String?
  let location: DeclarationLocation
}
