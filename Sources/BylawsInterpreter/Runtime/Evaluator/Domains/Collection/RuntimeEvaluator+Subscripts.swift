import BylawsSemantics

extension RuntimeEvaluator {
  func subscriptValue(
    _ receiver: RuntimeValue,
    key: RuntimeValue,
    at location: DeclarationLocation
  ) throws(RuntimeError) -> RuntimeValue {
    switch receiver {
    case let .optional(wrapped):
      guard let wrapped else { return .optional(nil) }
      return try subscriptValue(wrapped, key: key, at: location)
        .optionalChained
    case let .dictionary(values):
      return .optional(values[try RuntimeDictionaryKey(key, at: location)])
    case let .array(values):
      return try element(in: values, at: key, location: location)
    case let .arraySlice(values):
      return try element(in: values, at: key, location: location)
    case let .selection(selection):
      return .model(try element(
        in: selection.elements, at: key, location: location
      ))
    default:
      throw RuntimeError(
        message: "Subscript must have an Array, ArraySlice, Selection or Dictionary receiver",
        location: location
      )
    }
  }

  private func element<Values: RandomAccessCollection>(
    in values: Values,
    at key: RuntimeValue,
    location: DeclarationLocation
  ) throws(RuntimeError) -> Values.Element where Values.Index == Int {
    guard case let .integer(index) = key else {
      throw RuntimeError(
        message: "Subscript must use an Int index", location: location
      )
    }
    guard index >= values.startIndex, index < values.endIndex else {
      throw RuntimeError(
        message: "Subscript index must be within the collection",
        location: location
      )
    }
    return values[index]
  }
}
