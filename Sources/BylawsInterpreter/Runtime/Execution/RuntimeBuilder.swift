import BylawsCore
import BylawsSemantics

enum RuntimeBuilder {
  case correction
  case layout, sourceLayout
  case replacement
  case checks
  case rules, layers

  var argumentRequirement: String {
    switch self {
    case .correction: "Correction takes source operations, corrections, fixes or edit arrays"
    case .layout: "Layout takes source values, grouping or spacing policies"
    case .sourceLayout: "SourceLayout takes source values, layouts or source collections. Use Layout for grouping and spacing."
    case .replacement: "SourceReplacement takes captured source, replacement values or scopes"
    case .checks: "Rule takes check results"
    case .rules: "Array<Rule> takes Rule values or rule arrays"
    case .layers: "Layering takes Layer values or layer arrays"
    }
  }

  var resultType: SupportedAPI.RuntimeType {
    switch self {
    case .correction: .sourceCorrection
    case .layout: .layoutContent(.unknown)
    case .sourceLayout: .sourceLayout
    case .replacement: .sourceReplacement
    case .checks: .ruleResults
    case .rules: .array(.rule)
    case .layers: .layering
    }
  }

  func accepts(_ type: SupportedAPI.RuntimeType) -> Bool {
    switch self {
    case .layout: type.supportsLayout
    case .sourceLayout: type.supportsSourceLayout
    case .replacement: type.supportsReplacement
    case .correction:
      switch type {
      case .sourceCorrection, .layoutCorrection, .sourceFix, .sourceEdit: true
      case let .array(element): element == .unknown || accepts(element)
      default: false
      }
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
    case .replacement:
      return .sourceReplacement(SourceReplacement(combining: try values.map {
        value throws(RuntimeError) in try value.replacementContent(at: location)
      }))
    case .correction:
      return .sourceCorrection(SourceCorrection(combining: try values
          .map { value throws(RuntimeError) in
            try value.correction(at: location)
          }))
    case .sourceLayout:
      return .sourceLayout(SourceLayout(node: .sequence(try values
          .map { value throws(RuntimeError) in
            try value.layoutNode(at: location)
          })))
    case .layout:
      var operations: [RuntimeLayoutOperation] = []
      for value in values {
        operations.append(contentsOf: try value.layoutOperations(at: location))
      }
      return .layoutPlan(operations)
    case .rules, .layers:
      let elements = values.flatMap { value in
        switch value {
        case let .array(elements): elements
        default: [value]
        }
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
