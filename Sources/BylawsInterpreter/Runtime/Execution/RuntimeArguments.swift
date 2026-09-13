import BylawsSemantics

struct RuntimeArguments {
  let values: [(label: String?, value: RuntimeValue)]
  let location: DeclarationLocation

  func requireLabels(
    _ labels: [String?],
    for name: String
  ) throws(RuntimeError) {
    guard values.map(\.label) == labels else {
      throw RuntimeError(
        message: "'\(name)' takes arguments \(argumentLabelList(labels))",
        location: location
      )
    }
  }

  func requireLabels(
    _ labels: [SupportedAPI.ArgumentLabel?],
    for method: SupportedAPI.Method
  ) throws(RuntimeError) {
    try requireLabels(labels.map(\.written), for: method.rawValue)
  }

  func hasLabels(_ labels: [SupportedAPI.ArgumentLabel?]) -> Bool {
    values.map(\.label).equal(labels)
  }

  func label(at index: Int) -> SupportedAPI.ArgumentLabel? {
    guard values.indices.contains(index) else { return nil }
    return values[index].label.flatMap(SupportedAPI.ArgumentLabel.init)
  }

  func value(at index: Int) throws(RuntimeError) -> RuntimeValue {
    guard values.indices.contains(index) else {
      throw RuntimeError(
        message: "missing argument",
        location: location
      )
    }
    return values[index].value
  }

  func string(at index: Int) throws(RuntimeError) -> String {
    guard case let .string(value) = try value(at: index) else {
      throw typeFailure("String", at: index)
    }
    return value
  }

  func integer(at index: Int) throws(RuntimeError) -> Int {
    guard case let .integer(value) = try value(at: index) else {
      throw typeFailure("Int", at: index)
    }
    return value
  }

  func boolean(at index: Int) throws(RuntimeError) -> Bool {
    guard case let .boolean(value) = try value(at: index) else {
      throw typeFailure("Bool", at: index)
    }
    return value
  }

  func array(at index: Int) throws(RuntimeError) -> [RuntimeValue] {
    guard case let .array(value) = try value(at: index) else {
      throw typeFailure("Array", at: index)
    }
    return value
  }

  func sequence(at index: Int) throws(RuntimeError) -> [RuntimeValue] {
    guard let elements = try value(at: index).sequenceElements
    else { throw typeFailure(
      "a sequence",
      at: index
    ) }
    return elements
  }

  func strings(at index: Int) throws(RuntimeError) -> [String] {
    try array(at: index).map { value throws(RuntimeError) -> String in
      guard case let .string(value) = value else {
        throw typeFailure("[String]", at: index)
      }
      return value
    }
  }

  func closure(at index: Int) throws(RuntimeError) -> RuntimeClosure {
    guard case let .closure(value) = try value(at: index) else {
      throw typeFailure("closure", at: index)
    }
    return value
  }

  private func typeFailure(
    _ type: String,
    at index: Int
  ) -> RuntimeError {
    RuntimeError(
      message: "argument \(index + 1) must be \(type)",
      location: location
    )
  }
}
