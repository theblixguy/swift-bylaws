package final class MemberStorage: Sendable {
  package static let empty = MemberStorage(
    functions: [],
    properties: [],
    initializers: []
  )

  package let functions: [Function]
  package let properties: [Property]
  package let initializers: [Initializer]

  private let functionIndices: [String: [Int]]
  private let propertyIndices: [String: [Int]]
  private let initializerIndices: [String: [Int]]

  package init(
    functions: [Function],
    properties: [Property],
    initializers: [Initializer]
  ) {
    self.functions = functions
    self.properties = properties
    self.initializers = initializers
    functionIndices = Self.indicesByType(
      in: functions,
      enclosingTypeName: \.enclosingTypeName
    )
    propertyIndices = Self.indicesByType(
      in: properties,
      enclosingTypeName: \.enclosingTypeName
    )
    initializerIndices = Self.indicesByType(
      in: initializers,
      enclosingTypeName: \.enclosingTypeName
    )
  }

  package func functions(of typeName: String) -> MemberCollection<Function> {
    MemberCollection(
      elements: functions,
      indices: functionIndices[typeName] ?? []
    )
  }

  package func properties(of typeName: String) -> MemberCollection<Property> {
    MemberCollection(
      elements: properties,
      indices: propertyIndices[typeName] ?? []
    )
  }

  package func initializers(
    of typeName: String
  ) -> MemberCollection<Initializer> {
    MemberCollection(
      elements: initializers,
      indices: initializerIndices[typeName] ?? []
    )
  }

  private static func indicesByType<Element>(
    in declarations: [Element],
    enclosingTypeName: KeyPath<Element, String?>
  ) -> [String: [Int]] {
    var result: [String: [Int]] = [:]
    for (index, declaration) in declarations.enumerated() {
      guard let typeName = declaration[keyPath: enclosingTypeName] else {
        continue
      }
      result[typeName, default: []].append(index)
    }
    return result
  }
}
