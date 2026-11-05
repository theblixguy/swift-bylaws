import BylawsSemantics

extension RuntimeEvaluator {
  func layoutContent(
    _ method: SupportedAPI.Method, arguments: RuntimeArguments
  ) throws(RuntimeError) -> RuntimeValue {
    let value = try arguments.value(at: 0)
    switch method {
    case .sequence:
      guard case let .array(values) = value else {
        throw RuntimeError(
          message: "LayoutContent.sequence takes an array of layout components",
          location: arguments.location
        )
      }
      return try RuntimeBuilder.layout.combine(values, at: arguments.location)
    case .separator:
      let whitespace: SourceWhitespace = switch value {
      case .member(.constant(.newline)): .newline
      case .member(.constant(.blankLine)): .blankLine
      default: throw RuntimeError(
          wrapping: SourceListLayoutError.unsupportedSeparator,
          at: arguments.location
        )
      }
      return .layoutPlan([.separator(whitespace)])
    case .layout:
      return .layoutPlan([.layout(SourceLayout(node: try value
          .layoutNode(at: arguments.location)))])
    default: return value
    }
  }
}
