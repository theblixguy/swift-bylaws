import BylawsCore
import BylawsSemantics

enum RuntimeBuilder {
  case checks
  case rules, layers

  var argumentRequirement: String {
    switch self {
    case .checks: "Rule takes check results"
    case .rules: "Array<Rule> takes Rule values or rule arrays"
    case .layers: "Layering takes Layer values or layer arrays"
    }
  }

  var resultType: SupportedAPI.RuntimeType {
    switch self {
    case .checks: .ruleResults
    case .rules: .array(.rule)
    case .layers: .layering
    }
  }

  func accepts(_ type: SupportedAPI.RuntimeType) -> Bool {
    switch self {
    case .checks: type.isRuleResult
    case .rules: type == .rule || type.isAssignable(to: .array(.rule))
    case .layers: type == .layer || type.isAssignable(to: .array(.layer))
    }
  }

  func combine(
    _ values: [RuntimeValue],
    at location: DeclarationLocation
  ) throws(RuntimeError) -> RuntimeValue {
    switch self {
    case .rules, .layers:
      let elements = values.flatMap { value in
        if case let .array(elements) = value { elements } else { [value] }
      }
      if self == .rules {
        guard elements.allSatisfy({ $0.hasRuntimeType(.rule) }) else {
          throw RuntimeError(
            message: argumentRequirement,
            location: location
          )
        }
        return .array(elements)
      }
      let layers = try elements.map { value throws(RuntimeError) -> Layer in
        guard case let .layer(layer) = value else {
          throw RuntimeError(
            message: argumentRequirement,
            location: location
          )
        }
        return layer
      }
      return .layering(Layering(layers))
    case .checks: break
    }
    let results = try values
      .map { value throws(RuntimeError) -> any RuleResult in
        guard let result = value.ruleResult else {
          throw RuntimeError(
            message: argumentRequirement,
            location: location
          )
        }
        return result
      }
    return .ruleResults(RuleResults(results: results))
  }
}
