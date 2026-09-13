extension SupportedAPI {
  package struct Query: Sendable {
    package enum ID: String, CaseIterable, Hashable, Sendable {
      case files
      case classes
      case actors
      case structs
      case enums
      case types
      case protocols
      case extensions
      case functions
      case properties
      case initializers
      case imports
      case typealiases
      case calls
    }

    package let id: ID
    package let declarationFamily: DeclarationFamily

    package var name: String { id.rawValue }

    package var argumentContract: ArgumentContract { .none }
  }

  package static let queries: [Query] = [
    Query(id: .files, declarationFamily: .file),
    Query(id: .classes, declarationFamily: .class),
    Query(id: .actors, declarationFamily: .actor),
    Query(id: .structs, declarationFamily: .struct),
    Query(id: .enums, declarationFamily: .enum),
    Query(id: .types, declarationFamily: .nominalType),
    Query(id: .protocols, declarationFamily: .protocol),
    Query(
      id: .extensions,
      declarationFamily: .extension
    ),
    Query(id: .functions, declarationFamily: .function),
    Query(id: .properties, declarationFamily: .property),
    Query(
      id: .initializers,
      declarationFamily: .initializer
    ),
    Query(id: .imports, declarationFamily: .import),
    Query(
      id: .typealiases,
      declarationFamily: .typealias
    ),
    Query(id: .calls, declarationFamily: .functionCall),
  ]

  package static func query(named name: String) -> Query? {
    queries.first { $0.name == name }
  }
}
