import BylawsSemantics

extension RuntimeTypeResolver {
  mutating func resolveComparator(
    _ expression: RuntimeExpression,
    element: RuntimeType
  ) -> RuntimeType {
    let comparison: SupportedAPI.RuntimeClosureType? = switch expression.kind {
    case let .closure(definition):
      resolve(
        definition, parameters: [element, element],
        expectedResult: .boolean, requiresSynchronousBody: true,
        allowsThrowingBody: true
      )
    default:
      switch resolve(expression) {
      case let .function(function):
        SupportedAPI.RuntimeClosureType(
          parameters: function.parameters.map(\.type),
          result: function.result, isAsync: function.isAsync,
          isThrowing: function.isThrowing
        )
      case let .closure(closure): closure
      default: nil
      }
    }
    guard let comparison else {
      diagnose(
        "sorted takes a comparison closure or function",
        at: expression.location
      )
      return .unknown
    }
    if comparison.isAsync {
      diagnose(
        "the comparison must be synchronous", at: expression.location
      )
    }
    if comparison.parameters.count != 2 {
      diagnose(
        "the comparison takes two parameters", at: expression.location
      )
    }
    for parameter in comparison.parameters {
      require(
        element, toMatch: parameter,
        subject: "the collection element", at: expression.location
      )
    }
    require(
      comparison.result, toMatch: .boolean,
      subject: "the comparison", at: expression.location
    )
    requireEffects(
      canSuspend: false, canThrow: comparison.isThrowing,
      at: expression.location
    )
    return .boolean
  }
}
