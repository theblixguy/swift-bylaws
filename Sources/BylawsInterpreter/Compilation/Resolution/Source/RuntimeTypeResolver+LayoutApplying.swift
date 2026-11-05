import BylawsSemantics

extension RuntimeTypeResolver {
  mutating func resolveLayoutApplying(
    values: [(String?, RuntimeExpression)], at location: DeclarationLocation
  ) -> RuntimeType {
    if values.first?.0 == "toEach" {
      let lists = resolve(values[0].1)
      guard let collection = lists.sequenceElement,
            let element = collection.sequenceElement,
            element.providesSource
      else {
        diagnose(
          "applying takes collections of captured source with toEach:",
          at: location
        )
        _ = resolve(values[1].1)
        return .layoutCorrection
      }
      let outerElement = layoutElementType
      layoutElementType = element
      defer { layoutElementType = outerElement }
      resolveLayoutClosure(values[1].1, inputs: [collection])
      return .layoutCorrection
    }
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
