extension SupportedAPI {
  package struct Matcher: Sendable {
    package enum ID: String, CaseIterable, Hashable, Sendable {
      case named
      case suffixed
      case prefixed
      case nameMatching
      case inherits
      case directlyInherits
      case conforms
      case directlyConforms
      case declaresInheritance
      case isPublic
      case hasVisibility
      case hasAttribute
      case hasDocumentation
      case isFinal
      case isClass
      case isStruct
      case isEnum
      case isActor
      case isIndirect
      case isOverride
      case isMutating
      case isDynamic
      case isAsync
      case isThrowing
      case isNonisolated
      case returnsOptional
      case isConvenience
      case isWeak
      case isLazy
      case isNonisolatedUnsafe
      case hasOptionalType
      case hasType
      case referencesType
      case imports
      case calls
      case returns
      case hasParameter
      case references
      case hasArgumentLabel
    }

    package let id: ID
    package let arguments: ArgumentContract
    package let declarationFamilies: Set<DeclarationFamily>

    package var name: String { id.rawValue }
  }

  package static let matchers: [Matcher] = [
    Matcher(
      id: .named,
      arguments: .strings(startingWith: nil),
      declarationFamilies: allDeclarationFamilies
    ),
    Matcher(
      id: .suffixed,
      arguments: .strings(startingWith: nil),
      declarationFamilies: allDeclarationFamilies
    ),
    Matcher(
      id: .prefixed,
      arguments: .strings(startingWith: nil),
      declarationFamilies: allDeclarationFamilies
    ),
    Matcher(
      id: .nameMatching,
      arguments: .oneString(labelled: nil),
      declarationFamilies: allDeclarationFamilies
    ),
    Matcher(
      id: .inherits,
      arguments: .strings(startingWith: .from),
      declarationFamilies: inheritanceDeclarationFamilies
    ),
    Matcher(
      id: .directlyInherits,
      arguments: .strings(startingWith: .from),
      declarationFamilies: inheritanceDeclarationFamilies
    ),
    Matcher(
      id: .conforms,
      arguments: .strings(startingWith: .to),
      declarationFamilies: inheritanceDeclarationFamilies
    ),
    Matcher(
      id: .directlyConforms,
      arguments: .strings(startingWith: .to),
      declarationFamilies: inheritanceDeclarationFamilies
    ),
    Matcher(
      id: .declaresInheritance,
      arguments: .oneString(labelled: nil),
      declarationFamilies: inheritanceDeclarationFamilies
    ),
    Matcher(
      id: .isPublic,
      arguments: .none,
      declarationFamilies: visibleDeclarationFamilies
    ),
    Matcher(
      id: .hasVisibility,
      arguments: .visibility,
      declarationFamilies: visibleDeclarationFamilies
    ),
    Matcher(
      id: .hasAttribute,
      arguments: .strings(startingWith: nil),
      declarationFamilies: attributedDeclarationFamilies
    ),
    Matcher(
      id: .hasDocumentation,
      arguments: .none,
      declarationFamilies: documentedDeclarationFamilies
    ),
    Matcher(
      id: .isFinal,
      arguments: .none,
      declarationFamilies: [.class]
    ),
    Matcher(
      id: .isClass,
      arguments: .none,
      declarationFamilies: [.nominalType]
    ),
    Matcher(
      id: .isStruct,
      arguments: .none,
      declarationFamilies: [.nominalType]
    ),
    Matcher(
      id: .isEnum,
      arguments: .none,
      declarationFamilies: [.nominalType]
    ),
    Matcher(
      id: .isActor,
      arguments: .none,
      declarationFamilies: [.nominalType]
    ),
    Matcher(
      id: .isIndirect,
      arguments: .none,
      declarationFamilies: [.enum]
    ),
    Matcher(
      id: .isOverride,
      arguments: .none,
      declarationFamilies: [.function]
    ),
    Matcher(
      id: .isMutating,
      arguments: .none,
      declarationFamilies: [.function]
    ),
    Matcher(
      id: .isDynamic,
      arguments: .none,
      declarationFamilies: [.function, .property]
    ),
    Matcher(
      id: .isAsync,
      arguments: .none,
      declarationFamilies: [.function]
    ),
    Matcher(
      id: .isThrowing,
      arguments: .none,
      declarationFamilies: [.function]
    ),
    Matcher(
      id: .isNonisolated,
      arguments: .none,
      declarationFamilies: [.function, .property]
    ),
    Matcher(
      id: .returnsOptional,
      arguments: .none,
      declarationFamilies: [.function]
    ),
    Matcher(
      id: .isConvenience,
      arguments: .none,
      declarationFamilies: [.initializer]
    ),
    Matcher(
      id: .isWeak,
      arguments: .none,
      declarationFamilies: [.property]
    ),
    Matcher(
      id: .isLazy,
      arguments: .none,
      declarationFamilies: [.property]
    ),
    Matcher(
      id: .isNonisolatedUnsafe,
      arguments: .none,
      declarationFamilies: [.property]
    ),
    Matcher(
      id: .hasOptionalType,
      arguments: .none,
      declarationFamilies: [.property]
    ),
    Matcher(
      id: .hasType,
      arguments: .strings(startingWith: nil),
      declarationFamilies: [.property]
    ),
    Matcher(
      id: .referencesType,
      arguments: .strings(startingWith: nil),
      declarationFamilies: [.property]
    ),
    Matcher(
      id: .imports,
      arguments: .strings(startingWith: nil),
      declarationFamilies: [.file]
    ),
    Matcher(
      id: .calls,
      arguments: .strings(startingWith: nil),
      declarationFamilies: [.file, .function, .property]
    ),
    Matcher(
      id: .returns,
      arguments: .oneString(labelled: nil),
      declarationFamilies: [.function]
    ),
    Matcher(
      id: .hasParameter,
      arguments: .functionParameter,
      declarationFamilies: [.function]
    ),
    Matcher(
      id: .references,
      arguments: .strings(startingWith: nil),
      declarationFamilies: [.functionCall]
    ),
    Matcher(
      id: .hasArgumentLabel,
      arguments: .oneString(labelled: nil),
      declarationFamilies: [.functionCall]
    ),
  ]

  package static func matcher(named name: String) -> Matcher? {
    matchers.first { $0.name == name }
  }

  private static let inheritanceDeclarationFamilies: Set<DeclarationFamily> = [
    .class, .actor, .struct, .enum, .nominalType, .protocol,
  ]

  private static let visibleDeclarationFamilies: Set<DeclarationFamily> = [
    .class, .actor, .struct, .enum, .nominalType, .protocol, .extension,
    .function, .property, .initializer, .import, .typealias,
  ]

  private static let attributedDeclarationFamilies = visibleDeclarationFamilies

  private static let documentedDeclarationFamilies: Set<DeclarationFamily> = [
    .class, .actor, .struct, .enum, .nominalType, .protocol, .function,
    .property, .initializer, .typealias,
  ]
}
