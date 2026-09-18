extension SupportedAPI {
  package struct Filter: Sendable {
    package enum ID: String, CaseIterable, Hashable, Sendable {
      case named
      case suffixed
      case prefixed
      case excluding
      case under
      case outside
      case nameMatching
    }

    package let id: ID
    package let arguments: ArgumentContract

    package var name: String { id.rawValue }

    package var declarationFamilies: Set<DeclarationFamily> {
      SupportedAPI.queryDeclarationFamilies
    }

    package var requiresNames: Bool {
      id != .under && id != .outside
    }
  }

  package static let filters: [Filter] = [
    Filter(id: .named, arguments: .strings(startingWith: nil)),
    Filter(
      id: .suffixed,
      arguments: .strings(startingWith: nil)
    ),
    Filter(
      id: .prefixed,
      arguments: .strings(startingWith: nil)
    ),
    Filter(
      id: .excluding,
      arguments: .strings(startingWith: nil)
    ),
    Filter(id: .under, arguments: .strings(startingWith: nil)),
    Filter(
      id: .outside,
      arguments: .strings(startingWith: nil)
    ),
    Filter(
      id: .nameMatching,
      arguments: .oneString(labelled: nil)
    ),
  ]

  package static func filter(named name: String) -> Filter? {
    filters.first { $0.name == name }
  }
}
