struct RuntimeEnvironment: Sendable {
  private(set) var values: [String: RuntimeValue] = [:]

  subscript(name: String) -> RuntimeValue? {
    values[name]
  }

  mutating func bind(_ value: RuntimeValue, to name: String) {
    values[name] = value
  }

  mutating func merge(_ environment: RuntimeEnvironment) {
    values.merge(environment.values) { current, _ in current }
  }

  mutating func overlay(_ environment: RuntimeEnvironment) {
    values.merge(environment.values) { _, replacement in replacement }
  }

  func exporting(_ names: Set<String>) -> RuntimeEnvironment {
    var exported = RuntimeEnvironment()
    for name in names {
      guard let value = values[name] else { continue }
      exported.bind(value.capturingFunctions(in: self), to: name)
    }
    return exported
  }

  func resolvingRuleCaptures(
    excluding names: Set<String>
  ) -> RuntimeEnvironment {
    var globals = self
    for name in names {
      globals.values.removeValue(forKey: name)
    }
    var resolved = RuntimeEnvironment()
    for (name, value) in values {
      resolved.bind(value.resolvingRuleCaptures(with: globals), to: name)
    }
    return resolved
  }
}

extension RuntimeValue {
  func capturingFunctions(in environment: RuntimeEnvironment) -> RuntimeValue {
    guard case let .function(function) = self else { return self }
    return .function(function.capturing(environment))
  }

  func resolvingRuleCaptures(
    with globals: RuntimeEnvironment
  ) -> RuntimeValue {
    switch self {
    case let .array(values):
      .array(values.map { $0.resolvingRuleCaptures(with: globals) })
    case let .set(values):
      .set(values.map { $0.resolvingRuleCaptures(with: globals) })
    case let .rule(rule):
      .rule(rule.resolvingCaptures(with: globals))
    default:
      self
    }
  }
}
