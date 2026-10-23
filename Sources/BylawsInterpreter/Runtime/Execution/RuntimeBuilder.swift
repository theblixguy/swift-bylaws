import BylawsCore
import BylawsSemantics

enum RuntimeBuilder {
  case edits
  case layout
  case checks
  case rules, layers

  var argumentRequirement: String {
    switch self {
    case .edits: "withFix takes SourceFix, SourceFix.Edit or edit arrays"
    case .layout: "SourceLayout takes source values, layouts or source collections"
    case .checks: "Rule takes check results"
    case .rules: "Array<Rule> takes Rule values or rule arrays"
    case .layers: "Layering takes Layer values or layer arrays"
    }
  }

  var resultType: SupportedAPI.RuntimeType {
    switch self {
    case .edits: .array(.sourceEdit)
    case .layout: .sourceLayout
    case .checks: .ruleResults
    case .rules: .array(.rule)
    case .layers: .layering
    }
  }

  func accepts(_ type: SupportedAPI.RuntimeType) -> Bool {
    switch self {
    case .layout: type.supportsLayout
    case .edits: type == .sourceFix || type == .sourceEdit || type
      .isAssignable(to: .array(.sourceEdit))
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
    case .layout:
      if values.contains(where: {
        switch $0 {
        case .layoutPlan, .layoutGroup: true
        default: false
        }
      }) {
        var operations: [RuntimeLayoutOperation] = []
        for value in values {
          operations
            .append(contentsOf: try value.layoutOperations(at: location))
        }
        return .layoutPlan(operations)
      }
      var nodes: [SourceLayout.Node] = []
      for value in values {
        nodes.append(try value.layoutNode(at: location))
      }
      return .sourceLayout(SourceLayout(node: .sequence(nodes)))
    case .rules, .layers, .edits:
      let elements = values.flatMap { value in
        switch value {
        case let .array(elements): elements
        case let .sourceFix(fix): fix.edits.map(RuntimeValue.sourceEdit)
        default: [value]
        }
      }
      if self == .edits {
        guard elements.allSatisfy({ $0.hasRuntimeType(.sourceEdit) }) else {
          throw RuntimeError(message: argumentRequirement, location: location)
        }
        return .array(elements)
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
