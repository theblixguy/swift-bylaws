import BylawsSemantics

extension RuntimeTypeResolver {
  mutating func resolveSubscript(
    receiver: RuntimeType,
    key: RuntimeExpression,
    at location: DeclarationLocation
  ) -> RuntimeType {
    switch receiver {
    case let .optional(wrapped):
      return resolveSubscript(receiver: wrapped, key: key, at: location)
        .optionalChained
    case .array, .arraySlice, .selection:
      require(
        resolve(key, expected: .integer), toMatch: .integer,
        subject: "the collection index", at: key.location
      )
      return receiver.collectionElement
    case let .dictionary(keyType, valueType):
      require(
        resolve(key, expected: keyType), toMatch: keyType,
        subject: "the dictionary key", at: key.location
      )
      return .optional(valueType)
    default:
      diagnose(
        "Subscript must have an Array, ArraySlice, Selection or Dictionary receiver",
        at: location
      )
      _ = resolve(key)
      return .unknown
    }
  }
}
