import BylawsCore
import BylawsSemantics

extension RuntimeEvaluator {
  func modelMember(
    _ name: SupportedAPI.Member,
    of value: RuntimeModelValue
  ) -> RuntimeValue? {
    if name == .location, let location = value.offender?.location {
      return .model(.check(.location(location)))
    }
    return switch value {
    case let .check(value): checkMember(name, value)
    case let .sourceFile(value): sourceFileMember(name, value)
    case let .classDeclaration(value): classMember(name, value)
    case let .actor(value): typeMember(name, value)
    case let .structDeclaration(value): typeMember(name, value)
    case let .enumDeclaration(value): enumMember(name, value)
    case let .nominalType(value): nominalTypeMember(name, value)
    case let .protocolDeclaration(value): protocolMember(name, value)
    case let .extensionDeclaration(value): extensionMember(name, value)
    case let .function(value): functionMember(name, value)
    case let .property(value): propertyMember(name, value)
    case let .initializer(value): initializerMember(name, value)
    case let .importDeclaration(value): importMember(name, value)
    case let .typealiasDeclaration(value): typealiasMember(name, value)
    case let .functionCall(value): callMember(name, value)
    case let .typeReference(value): typeReferenceMember(name, value)
    case let .parameter(value): parameterMember(name, value)
    case let .attribute(value): attributeMember(name, value)
    case let .genericParameter(value): genericParameterMember(name, value)
    case let .enumCase(value): enumCaseMember(name, value)
    case let .importGraph(value):
      name == .targets
        ? .array(value.targets.map { .model(.importGraphTarget($0)) }) : nil
    case let .importGraphTarget(value):
      importGraphTargetMember(name, value)
    case let .packageManifest(value): packageManifestMember(name, value)
    case let .manifest(value):
      manifestMember(name, value)
    case let .indexReference(value):
      indexReferenceMember(name, value)
    case let .indexSymbol(value):
      indexSymbolMember(name, value)
    case let .offender(value): offenderMember(name, value)
    case let .syntaxClass(value):
      syntaxClassMember(name, value)
    case let .syntaxMemberBlock(value):
      syntaxMemberBlockMember(name, value)
    case .syntaxSourceFile:
      nil
    case let .syntaxToken(value):
      syntaxTokenMember(name, value)
    case let .syntaxTriviaPiece(value):
      syntaxTriviaMember(name, value)
    }
  }

  private func sourceFileMember(
    _ name: SupportedAPI.Member,
    _ value: SourceFile
  ) -> RuntimeValue? {
    switch name {
    case .path: .string(value.path)
    case .sourceText: .string(value.sourceText)
    case .lineCount: .integer(value.lineCount)
    case .name: .string(value.name)
    case .imports: modelArray(
        value.imports,
        RuntimeModelValue.importDeclaration
      )
    case .classes: modelArray(value.classes, RuntimeModelValue.classDeclaration)
    case .actors: modelArray(value.actors, RuntimeModelValue.actor)
    case .structs: modelArray(
        value.structs,
        RuntimeModelValue.structDeclaration
      )
    case .enums: modelArray(value.enums, RuntimeModelValue.enumDeclaration)
    case .types: modelArray(value.types, RuntimeModelValue.nominalType)
    case .protocols:
      modelArray(value.protocols, RuntimeModelValue.protocolDeclaration)
    case .extensions:
      modelArray(value.extensions, RuntimeModelValue.extensionDeclaration)
    case .functions: modelArray(value.functions, RuntimeModelValue.function)
    case .properties: modelArray(value.properties, RuntimeModelValue.property)
    case .initializers:
      modelArray(value.initializers, RuntimeModelValue.initializer)
    case .typealiases:
      modelArray(value.typealiases, RuntimeModelValue.typealiasDeclaration)
    case .calls: modelArray(value.calls, RuntimeModelValue.functionCall)
    default: nil
    }
  }

  private func offenderMember(
    _ name: SupportedAPI.Member,
    _ value: Offender
  ) -> RuntimeValue? {
    switch name {
    case .description: .string(value.description)
    case .name: optionalString(value.name)
    case .path: .string(value.location.filePath)
    case .affectedPath: optionalString(value.affectedPath)
    case .requirement: optionalString(value.requirement)
    case .line: .integer(value.location.line)
    default: nil
    }
  }

  private func classMember(
    _ name: SupportedAPI.Member,
    _ value: Class
  ) -> RuntimeValue? {
    typeMember(name, value).or {
      switch name {
      case .isFinal: .boolean(value.isFinal)
      default: nil
      }
    }
  }

  private func enumMember(
    _ name: SupportedAPI.Member,
    _ value: Enum
  ) -> RuntimeValue? {
    typeMember(name, value).or {
      switch name {
      case .isIndirect: .boolean(value.isIndirect)
      case .cases: modelArray(value.cases, RuntimeModelValue.enumCase)
      default: nil
      }
    }
  }

  private func nominalTypeMember(
    _ name: SupportedAPI.Member,
    _ value: NominalType
  ) -> RuntimeValue? {
    typeMember(name, value).or {
      switch name {
      case .keyword: .string(value.keyword)
      case .isClass: .boolean(value.isClass)
      case .isStruct: .boolean(value.isStruct)
      case .isEnum: .boolean(value.isEnum)
      case .isActor: .boolean(value.isActor)
      default: nil
      }
    }
  }

  private func protocolMember(
    _ name: SupportedAPI.Member,
    _ value: ProtocolDeclaration
  ) -> RuntimeValue? {
    declarationMember(name, value).or {
      switch name {
      case .inheritedTypes: strings(value.inheritedTypes)
      case .extensionInheritedTypes: strings(value.extensionInheritedTypes)
      case .allInheritedTypes: strings(value.allInheritedTypes)
      case .sourceText: .string(value.sourceText)
      case .sourceRange: .integerRange(value.sourceRange)
      case .isNonisolated: .boolean(value.isNonisolated)
      case .requiredFunctions:
        modelArray(value.requiredFunctions, RuntimeModelValue.function)
      case .requiredProperties:
        modelArray(value.requiredProperties, RuntimeModelValue.property)
      default: nil
      }
    }
  }

  private func extensionMember(
    _ name: SupportedAPI.Member,
    _ value: Extension
  ) -> RuntimeValue? {
    switch name {
    case .name: .string(value.name)
    case .extendedTypeName: .string(value.extendedTypeName)
    case .simpleExtendedTypeName: .string(value.simpleExtendedTypeName)
    case .inheritedTypes: strings(value.inheritedTypes)
    case .allInheritedTypes: strings(value.allInheritedTypes)
    case .visibility: .member(naming: value.visibility)
    case .attributes: modelArray(value.attributes, RuntimeModelValue.attribute)
    default: nil
    }
  }

  private func functionMember(
    _ name: SupportedAPI.Member,
    _ value: Function
  ) -> RuntimeValue? {
    declarationMember(name, value).or {
      switch name {
      case .parameters: modelArray(
          value.parameters,
          RuntimeModelValue.parameter
        )
      case .returnType:
        optionalModel(
          value.returnType,
          RuntimeModelValue.typeReference
        )
      case .returnTypeName: optionalString(value.returnTypeName)
      case .enclosingTypeName: optionalString(value.enclosingTypeName)
      case .isStatic: .boolean(value.isStatic)
      case .isOverride: .boolean(value.isOverride)
      case .isMutating: .boolean(value.isMutating)
      case .isDynamic: .boolean(value.isDynamic)
      case .isAsync: .boolean(value.isAsync)
      case .isThrowing: .boolean(value.isThrowing)
      case .isNonisolated: .boolean(value.isNonisolated)
      case .calls: modelArray(value.calls, RuntimeModelValue.functionCall)
      case .bodyLineCount: .integer(value.bodyLineCount)
      case .awaitCount: .integer(value.awaitCount)
      case .cyclomaticComplexity: .integer(value.cyclomaticComplexity)
      case .sourceText: .string(value.sourceText)
      case .genericParameters:
        modelArray(value.genericParameters, RuntimeModelValue.genericParameter)
      case .sourceRange: .integerRange(value.sourceRange)
      default: nil
      }
    }
  }

  private func propertyMember(
    _ name: SupportedAPI.Member,
    _ value: Property
  ) -> RuntimeValue? {
    declarationMember(name, value).or {
      switch name {
      case .type: optionalModel(value.type, RuntimeModelValue.typeReference)
      case .typeName: optionalString(value.typeName)
      case .isConstant: .boolean(value.isConstant)
      case .isStatic: .boolean(value.isStatic)
      case .ownership:
        .optional(value.ownership.flatMap { RuntimeValue.member(naming: $0) })
      case .isWeak: .boolean(value.isWeak)
      case .isLazy: .boolean(value.isLazy)
      case .isDynamic: .boolean(value.isDynamic)
      case .isNonisolated: .boolean(value.isNonisolated)
      case .isNonisolatedUnsafe: .boolean(value.isNonisolatedUnsafe)
      case .calls: modelArray(value.calls, RuntimeModelValue.functionCall)
      default: nil
      }
    }
  }

  private func initializerMember(
    _ name: SupportedAPI.Member,
    _ value: Initializer
  ) -> RuntimeValue? {
    declarationMember(name, value).or {
      switch name {
      case .parameters: modelArray(
          value.parameters,
          RuntimeModelValue.parameter
        )
      case .isFailable: .boolean(value.isFailable)
      case .isConvenience: .boolean(value.isConvenience)
      case .isAsync: .boolean(value.isAsync)
      case .isThrowing: .boolean(value.isThrowing)
      case .isNonisolated: .boolean(value.isNonisolated)
      case .calls: modelArray(value.calls, RuntimeModelValue.functionCall)
      case .awaitCount: .integer(value.awaitCount)
      case .cyclomaticComplexity: .integer(value.cyclomaticComplexity)
      default: nil
      }
    }
  }

  private func importMember(
    _ name: SupportedAPI.Member,
    _ value: Import
  ) -> RuntimeValue? {
    switch name {
    case .name: .string(value.name)
    case .moduleName: .string(value.moduleName)
    case .kind:
      .optional(value.kind.flatMap { RuntimeValue.member(naming: $0) })
    case .visibility: .member(naming: value.visibility)
    case .attributes: modelArray(value.attributes, RuntimeModelValue.attribute)
    default: nil
    }
  }

  private func typealiasMember(
    _ name: SupportedAPI.Member,
    _ value: Typealias
  ) -> RuntimeValue? {
    declarationMember(name, value).or {
      switch name {
      case .aliasedTypeName: .string(value.aliasedTypeName)
      default: nil
      }
    }
  }

  private func callMember(
    _ name: SupportedAPI.Member,
    _ value: FunctionCall
  ) -> RuntimeValue? {
    switch name {
    case .name: .string(value.name)
    case .calledExpression: .string(value.calledExpression)
    case .baseName: .string(value.baseName)
    case .memberName: .string(value.memberName)
    case .argumentLabels:
      .array(value.argumentLabels.map(optionalString))
    default: nil
    }
  }

  private func typeReferenceMember(
    _ name: SupportedAPI.Member,
    _ value: TypeReference
  ) -> RuntimeValue? {
    switch name {
    case .text: .string(value.text)
    case .name: .string(value.name)
    case .isOptional: .boolean(value.isOptional)
    case .isArray: .boolean(value.isArray)
    case .isDictionary: .boolean(value.isDictionary)
    case .isSet: .boolean(value.isSet)
    case .isExistential: .boolean(value.isExistential)
    case .isOpaque: .boolean(value.isOpaque)
    case .isFunction: .boolean(value.isFunction)
    case .isTuple: .boolean(value.isTuple)
    case .genericArguments:
      modelArray(value.genericArguments, RuntimeModelValue.typeReference)
    case .elementType:
      optionalModel(
        value.elementType,
        RuntimeModelValue.typeReference
      )
    case .keyType: optionalModel(value.keyType, RuntimeModelValue.typeReference)
    case .valueType:
      optionalModel(
        value.valueType,
        RuntimeModelValue.typeReference
      )
    default: nil
    }
  }

  private func parameterMember(
    _ name: SupportedAPI.Member,
    _ value: Parameter
  ) -> RuntimeValue? {
    switch name {
    case .label: optionalString(value.label)
    case .name: .string(value.name)
    case .type: .model(.typeReference(value.type))
    case .typeName: .string(value.typeName)
    default: nil
    }
  }

  private func attributeMember(
    _ name: SupportedAPI.Member,
    _ value: Attribute
  ) -> RuntimeValue? {
    switch name {
    case .name: .string(value.name)
    case .arguments: optionalString(value.arguments)
    default: nil
    }
  }

  private func genericParameterMember(
    _ name: SupportedAPI.Member,
    _ value: GenericParameter
  ) -> RuntimeValue? {
    switch name {
    case .name: .string(value.name)
    case .constraintName: optionalString(value.constraintName)
    default: nil
    }
  }

  private func enumCaseMember(
    _ name: SupportedAPI.Member,
    _ value: EnumCase
  ) -> RuntimeValue? {
    switch name {
    case .name: .string(value.name)
    case .isIndirect: .boolean(value.isIndirect)
    case .rawValue: optionalString(value.rawValue)
    case .enclosingTypeName: optionalString(value.enclosingTypeName)
    case .documentation: optionalString(value.documentation)
    case .isDocumented: .boolean(value.isDocumented)
    default: nil
    }
  }

  private func importGraphTargetMember(
    _ name: SupportedAPI.Member,
    _ value: ImportGraph.Target
  ) -> RuntimeValue? {
    switch name {
    case .name: .string(value.name)
    case .imports: strings(value.imports)
    case .importedBy: strings(value.importedBy)
    case .instability: .double(value.instability)
    default: nil
    }
  }

  private func typeMember(
    _ name: SupportedAPI.Member,
    _ value: some TypeDeclaration & Documented
  ) -> RuntimeValue? {
    declarationMember(name, value).or {
      switch name {
      case .qualifiedName: .string(value.qualifiedName)
      case .enclosingTypeName: optionalString(value.enclosingTypeName)
      case .isNonisolated: .boolean(value.isNonisolated)
      case .inheritedTypes: strings(value.inheritedTypes)
      case .extensionInheritedTypes: strings(value.extensionInheritedTypes)
      case .allInheritedTypes: strings(value.allInheritedTypes)
      case .properties: modelArray(value.properties, RuntimeModelValue.property)
      case .functions: modelArray(value.functions, RuntimeModelValue.function)
      case .initializers:
        modelArray(value.initializers, RuntimeModelValue.initializer)
      case .genericParameters:
        modelArray(value.genericParameters, RuntimeModelValue.genericParameter)
      case .sourceRange: .integerRange(value.sourceRange)
      case .sourceText: .string(value.sourceText)
      default: nil
      }
    }
  }

  private func declarationMember(
    _ name: SupportedAPI.Member,
    _ value: some Named & Visible & Attributed & Documented
  ) -> RuntimeValue? {
    switch name {
    case .name: .string(value.name)
    case .visibility: .member(naming: value.visibility)
    case .attributes: modelArray(value.attributes, RuntimeModelValue.attribute)
    case .documentation: optionalString(value.documentation)
    case .isDocumented: .boolean(value.isDocumented)
    default: nil
    }
  }

  func modelArray<Element>(
    _ elements: some Sequence<Element>,
    _ transform: (Element) -> RuntimeModelValue
  ) -> RuntimeValue {
    .array(elements.map { .model(transform($0)) })
  }

  private func strings(_ values: [String]) -> RuntimeValue {
    .array(values.map(RuntimeValue.string))
  }

  func optionalString(_ value: String?) -> RuntimeValue {
    .optional(value.map(RuntimeValue.string))
  }

  func optionalModel<Element>(
    _ value: Element?,
    _ transform: (Element) -> RuntimeModelValue
  ) -> RuntimeValue {
    .optional(value.map { .model(transform($0)) })
  }
}

extension Optional {
  fileprivate func or(_ other: () -> Wrapped?) -> Wrapped? {
    self ?? other()
  }
}
