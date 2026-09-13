extension SupportedAPI {
  static let modelRuntimeMembers: [RuntimeMemberAPI] = [
    property(.path, on: [.model(.sourceFile)], result: .fixed(.string)),
    property(.sourceText, on: [.model(.sourceFile)], result: .fixed(.string)),
    property(.lineCount, on: [.model(.sourceFile)], result: .fixed(.integer)),
    property(.name, on: [.model(.sourceFile)], result: .fixed(.string)),
    modelArray(.imports, on: .sourceFile, element: .importDeclaration),
    modelArray(.classes, on: .sourceFile, element: .classDeclaration),
    modelArray(.actors, on: .sourceFile, element: .actor),
    modelArray(.structs, on: .sourceFile, element: .structDeclaration),
    modelArray(.enums, on: .sourceFile, element: .enumDeclaration),
    modelArray(.types, on: .sourceFile, element: .nominalType),
    modelArray(.protocols, on: .sourceFile, element: .protocolDeclaration),
    modelArray(.extensions, on: .sourceFile, element: .extensionDeclaration),
    modelArray(.functions, on: .sourceFile, element: .function),
    modelArray(.properties, on: .sourceFile, element: .property),
    modelArray(.initializers, on: .sourceFile, element: .initializer),
    modelArray(.typealiases, on: .sourceFile, element: .typealiasDeclaration),
    modelArray(.calls, on: .sourceFile, element: .functionCall),

    property(
      .name,
      on: declarationReceivers.union([
        .model(.extensionDeclaration), .model(.importDeclaration),
      ]),
      result: .fixed(.string)
    ),
    property(
      .visibility,
      on: attributedReceivers,
      result: .fixed(.staticMember([.visibility]))
    ),
    property(
      .attributes,
      on: attributedReceivers,
      result: .fixed(.array(.model(.attribute)))
    ),
    property(
      .documentation,
      on: declarationReceivers,
      result: .fixed(.optional(.string))
    ),
    property(
      .isDocumented,
      on: declarationReceivers,
      result: .fixed(.boolean)
    ),
    property(.qualifiedName, on: typeReceivers, result: .fixed(.string)),
    property(
      .inheritedTypes,
      on: inheritedTypeReceivers,
      result: .fixed(.array(.string))
    ),
    property(
      .extensionInheritedTypes,
      on: typeReceivers.union([.model(.protocolDeclaration)]),
      result: .fixed(.array(.string))
    ),
    property(
      .allInheritedTypes,
      on: inheritedTypeReceivers,
      result: .fixed(.array(.string))
    ),
    property(
      .genericParameters,
      on: typeReceivers.union([.model(.function)]),
      result: .fixed(.array(.model(.genericParameter)))
    ),
    property(
      .sourceRange,
      on: typeReceivers.union([
        .model(.function), .model(.protocolDeclaration),
      ]),
      result: .fixed(.integerRange)
    ),
    property(
      .properties,
      on: typeReceivers,
      result: .fixed(.array(.model(.property)))
    ),
    property(
      .functions,
      on: typeReceivers,
      result: .fixed(.array(.model(.function)))
    ),
    property(
      .initializers,
      on: typeReceivers,
      result: .fixed(.array(.model(.initializer)))
    ),
    property(
      .sourceText,
      on: typeReceivers.union([.model(.protocolDeclaration)]),
      result: .fixed(.string)
    ),
    property(
      .isFinal,
      on: [.model(.classDeclaration)],
      result: .fixed(.boolean)
    ),
    property(
      .isIndirect,
      on: [.model(.enumDeclaration)],
      result: .fixed(.boolean)
    ),
    property(
      .cases,
      on: [.model(.enumDeclaration)],
      result: .fixed(.array(.model(.enumCase)))
    ),
    property(.keyword, on: [.model(.nominalType)], result: .fixed(.string)),
    property(.isClass, on: [.model(.nominalType)], result: .fixed(.boolean)),
    property(.isStruct, on: [.model(.nominalType)], result: .fixed(.boolean)),
    property(.isEnum, on: [.model(.nominalType)], result: .fixed(.boolean)),
    property(.isActor, on: [.model(.nominalType)], result: .fixed(.boolean)),
    property(
      .isNonisolated,
      on: typeReceivers.union([.model(.protocolDeclaration)]),
      result: .fixed(.boolean)
    ),
    property(
      .enclosingTypeName,
      on: typeReceivers.union([.model(.function)]),
      result: .fixed(.optional(.string))
    ),

    property(
      .requiredFunctions,
      on: [.model(.protocolDeclaration)],
      result: .fixed(.array(.model(.function)))
    ),
    property(
      .requiredProperties,
      on: [.model(.protocolDeclaration)],
      result: .fixed(.array(.model(.property)))
    ),
    property(
      .extendedTypeName,
      on: [.model(.extensionDeclaration)],
      result: .fixed(.string)
    ),
    property(
      .simpleExtendedTypeName,
      on: [.model(.extensionDeclaration)],
      result: .fixed(.string)
    ),

    modelArray(.parameters, on: .function, element: .parameter),
    property(
      .returnType,
      on: [.model(.function)],
      result: .fixed(.optional(.model(.typeReference)))
    ),
    property(
      .returnTypeName,
      on: [.model(.function)],
      result: .fixed(.optional(.string))
    ),
    modelArray(.calls, on: .function, element: .functionCall),
    property(
      .bodyLineCount,
      on: [.model(.function)],
      result: .fixed(.integer)
    ),
    property(.awaitCount, on: [.model(.function)], result: .fixed(.integer)),
    property(
      .cyclomaticComplexity,
      on: [.model(.function)],
      result: .fixed(.integer)
    ),
    property(.sourceText, on: [.model(.function)], result: .fixed(.string)),

    property(
      .type,
      on: [.model(.property)],
      result: .fixed(.optional(.model(.typeReference)))
    ),
    property(
      .typeName,
      on: [.model(.property)],
      result: .fixed(.optional(.string))
    ),
    property(
      .ownership,
      on: [.model(.property)],
      result: .fixed(.optional(.staticMember([.ownership])))
    ),
    modelArray(.calls, on: .property, element: .functionCall),

    modelArray(.parameters, on: .initializer, element: .parameter),
    modelArray(.calls, on: .initializer, element: .functionCall),
    property(
      .awaitCount,
      on: [.model(.initializer)],
      result: .fixed(.integer)
    ),
    property(
      .cyclomaticComplexity,
      on: [.model(.initializer)],
      result: .fixed(.integer)
    ),

    property(
      .moduleName,
      on: [.model(.importDeclaration)],
      result: .fixed(.string)
    ),
    property(
      .kind,
      on: [.model(.importDeclaration)],
      result: .fixed(.optional(.staticMember([.importKind])))
    ),
    property(
      .aliasedTypeName,
      on: [.model(.typealiasDeclaration)],
      result: .fixed(.string)
    ),

    property(.name, on: [.model(.functionCall)], result: .fixed(.string)),
    property(
      .calledExpression,
      on: [.model(.functionCall)],
      result: .fixed(.string)
    ),
    property(.baseName, on: [.model(.functionCall)], result: .fixed(.string)),
    property(
      .memberName,
      on: [.model(.functionCall)],
      result: .fixed(.string)
    ),
    property(
      .argumentLabels,
      on: [.model(.functionCall)],
      result: .fixed(.array(.optional(.string)))
    ),

    property(.text, on: [.model(.typeReference)], result: .fixed(.string)),
    property(.name, on: [.model(.typeReference)], result: .fixed(.string)),
    property(
      .genericArguments,
      on: [.model(.typeReference)],
      result: .fixed(.array(.model(.typeReference)))
    ),
    property(
      .elementType,
      on: [.model(.typeReference)],
      result: .fixed(.optional(.model(.typeReference)))
    ),
    property(
      .keyType,
      on: [.model(.typeReference)],
      result: .fixed(.optional(.model(.typeReference)))
    ),
    property(
      .valueType,
      on: [.model(.typeReference)],
      result: .fixed(.optional(.model(.typeReference)))
    ),

    property(
      .label,
      on: [.model(.parameter)],
      result: .fixed(.optional(.string))
    ),
    property(.name, on: [.model(.parameter)], result: .fixed(.string)),
    property(
      .type,
      on: [.model(.parameter)],
      result: .fixed(.model(.typeReference))
    ),
    property(.typeName, on: [.model(.parameter)], result: .fixed(.string)),
    property(.name, on: [.model(.attribute)], result: .fixed(.string)),
    property(
      .arguments,
      on: [.model(.attribute)],
      result: .fixed(.optional(.string))
    ),

    property(.name, on: [.model(.genericParameter)], result: .fixed(.string)),
    property(
      .constraintName,
      on: [.model(.genericParameter)],
      result: .fixed(.optional(.string))
    ),
    property(.name, on: [.model(.enumCase)], result: .fixed(.string)),
    property(.isIndirect, on: [.model(.enumCase)], result: .fixed(.boolean)),
    property(
      .rawValue,
      on: [.model(.enumCase)],
      result: .fixed(.optional(.string))
    ),
    property(
      .enclosingTypeName,
      on: [.model(.enumCase)],
      result: .fixed(.optional(.string))
    ),
    property(
      .documentation,
      on: [.model(.enumCase)],
      result: .fixed(.optional(.string))
    ),
    property(
      .isDocumented,
      on: [.model(.enumCase)],
      result: .fixed(.boolean)
    ),

  ] + booleanProperties(
    [.isStatic, .isOverride, .isMutating, .isDynamic, .isAsync,
     .isThrowing, .isNonisolated],
    on: .function
  ) + booleanProperties(
    [.isConstant, .isStatic, .isWeak, .isLazy, .isDynamic,
     .isNonisolated, .isNonisolatedUnsafe],
    on: .property
  ) + booleanProperties(
    [.isFailable, .isConvenience, .isAsync, .isThrowing, .isNonisolated],
    on: .initializer
  ) + booleanProperties(
    [.isOptional, .isArray, .isDictionary, .isSet, .isExistential,
     .isOpaque, .isFunction, .isTuple],
    on: .typeReference
  )

  private static func modelArray(
    _ name: Member,
    on receiver: ModelType,
    element: ModelType
  ) -> RuntimeMemberAPI {
    property(
      name,
      on: [.model(receiver)],
      result: .fixed(.array(.model(element)))
    )
  }

  private static func booleanProperties(
    _ names: [Member],
    on receiver: ModelType
  ) -> [RuntimeMemberAPI] {
    names.map {
      property($0, on: [.model(receiver)], result: .fixed(.boolean))
    }
  }
}
