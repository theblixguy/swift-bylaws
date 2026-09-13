import BylawsSemantics

extension RuntimeTypeResolver {
  mutating func resolveDictionary(
    typeArguments: [RuntimeType],
    values: [(String?, RuntimeExpression)],
    at location: DeclarationLocation
  ) -> RuntimeType {
    if !typeArguments.isEmpty, typeArguments.count != 2 {
      diagnose("Dictionary takes two generic arguments", at: location)
    }
    guard values.map(\.0).equal([.grouping, .by])
      || values.map(\.0).equal([.grouping, nil])
    else {
      diagnose("Dictionary takes arguments (grouping:, by:)", at: location)
      values.forEach { _ = resolve($0.1) }
      return .unknown
    }
    let expectedValues: RuntimeType? = if typeArguments.count == 2 {
      typeArguments[1]
    } else {
      nil
    }
    guard let element = resolve(values[0].1, expected: expectedValues)
      .sequenceElement
    else {
      diagnose(
        "Dictionary grouping must be a sequence",
        at: values[0].1.location
      )
      _ = resolve(values[1].1)
      return .unknown
    }
    let key = resolveCallable(
      values[1].1, input: element,
      expectedResult: typeArguments.first, at: location
    )
    if !key.isDictionaryKey {
      diagnose(
        "Dictionary keys must be String, Int, Bool or URL",
        at: values[1].1.location
      )
    }
    let result: RuntimeType = .dictionary(key: key, value: .array(element))
    if typeArguments.count == 2 {
      require(
        result,
        toMatch: .dictionary(key: typeArguments[0], value: typeArguments[1]),
        subject: "the grouped dictionary", at: location
      )
    }
    return result
  }

  mutating func resolveSubscript(
    receiver: RuntimeType,
    key: RuntimeExpression,
    at location: DeclarationLocation
  ) -> RuntimeType {
    if case let .optional(wrapped) = receiver {
      return resolveSubscript(receiver: wrapped, key: key, at: location)
        .optionalChained
    }
    guard case let .dictionary(keyType, valueType) = receiver else {
      diagnose("Subscript must have a Dictionary receiver", at: location)
      _ = resolve(key)
      return .unknown
    }
    require(
      resolve(key, expected: keyType),
      toMatch: keyType,
      subject: "the dictionary key",
      at: key.location
    )
    return .optional(valueType)
  }
}

extension SupportedAPI.RuntimeType {
  var isDictionaryKey: Bool {
    switch self {
    case .string, .integer, .boolean, .url: true
    default: false
    }
  }
}
