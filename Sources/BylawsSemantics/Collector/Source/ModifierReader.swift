import SwiftSyntax

struct ModifierReader {
  let visibility: Visibility
  let isFinal: Bool
  let isStatic: Bool
  let isOverride: Bool
  let isLazy: Bool
  let isMutating: Bool
  let isConvenience: Bool
  let isDynamic: Bool
  let isIndirect: Bool
  let isNonisolated: Bool
  let isNonisolatedUnsafe: Bool
  let ownership: Ownership?

  init(
    _ modifiers: DeclModifierListSyntax,
    defaultVisibility: Visibility = .internal
  ) {
    var visibility = defaultVisibility
    var isFinal = false
    var isStatic = false
    var isOverride = false
    var isLazy = false
    var isMutating = false
    var isConvenience = false
    var isDynamic = false
    var isIndirect = false
    var isNonisolated = false
    var isNonisolatedUnsafe = false
    var ownership: Ownership?
    for modifier in modifiers {
      let isSetterScoped = modifier.detail != nil
      switch modifier.name.tokenKind {
      case .keyword(.private) where !isSetterScoped: visibility = .private
      case .keyword(.fileprivate) where !isSetterScoped:
        visibility = .fileprivate
      case .keyword(.package) where !isSetterScoped: visibility = .package
      case .keyword(.public) where !isSetterScoped: visibility = .public
      case .keyword(.open) where !isSetterScoped: visibility = .open
      case .keyword(.final): isFinal = true
      case .keyword(.static), .keyword(.class): isStatic = true
      case .keyword(.override): isOverride = true
      case .keyword(.lazy): isLazy = true
      case .keyword(.mutating): isMutating = true
      case .keyword(.convenience): isConvenience = true
      case .keyword(.dynamic): isDynamic = true
      case .keyword(.indirect): isIndirect = true
      case .keyword(.nonisolated):
        isNonisolated = true
        isNonisolatedUnsafe = modifier.detail?.detail.text == "unsafe"
      case .keyword(.weak): ownership = .weak
      case .keyword(.unowned): ownership = .unowned
      default: continue
      }
    }
    self.visibility = visibility
    self.isFinal = isFinal
    self.isStatic = isStatic
    self.isOverride = isOverride
    self.isLazy = isLazy
    self.isMutating = isMutating
    self.isConvenience = isConvenience
    self.isDynamic = isDynamic
    self.isIndirect = isIndirect
    self.isNonisolated = isNonisolated
    self.isNonisolatedUnsafe = isNonisolatedUnsafe
    self.ownership = ownership
  }

  static func attributes(_ attributes: AttributeListSyntax) -> [Attribute] {
    attributes.compactMap { element in
      guard case let .attribute(attribute) = element else { return nil }
      return Attribute(
        name: attribute.attributeName.trimmedDescription,
        arguments: attribute.arguments?.trimmedDescription
      )
    }
  }
}
