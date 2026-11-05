import BylawsSemantics

extension RuntimeTypeResolver {
  mutating func resolveLayoutApplying(
    values: [(String?, RuntimeExpression)], at location: DeclarationLocation
  ) -> RuntimeType {
    let expression = values[0].1
    let result: RuntimeType
    switch expression.kind {
    case let .closure(body):
      result = resolve(
        body,
        parameters: [],
        expectedResult: nil,
        requiresSynchronousBody: true,
        allowsThrowingBody: true,
        builder: .correction
      ).result
    default:
      let type = resolve(expression)
      switch type {
      case let .function(function):
        if !function.parameters.isEmpty || function.isAsync {
          diagnose(
            "applying takes a synchronous closure with no parameters",
            at: location
          )
        }
        result = function.result
      case let .closure(closure):
        if !closure.parameters.isEmpty || closure.isAsync {
          diagnose(
            "applying takes a synchronous closure with no parameters",
            at: location
          )
        }
        result = closure.result
      default: result = type
      }
    }
    if !RuntimeBuilder.correction.accepts(result) {
      diagnose(RuntimeBuilder.correction.argumentRequirement, at: location)
    }
    return .layoutCorrection
  }
}
