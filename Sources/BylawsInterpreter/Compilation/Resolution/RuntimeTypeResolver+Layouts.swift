import BylawsSemantics

extension RuntimeTypeResolver {
  mutating func resolveLayoutConstructor(
    _ constructor: SupportedAPI.Constructor,
    values: [(String?, RuntimeExpression)],
    at location: DeclarationLocation
  ) -> RuntimeType {
    if constructor == .newline || constructor == .blankLine || constructor ==
      .softBreak
    {
      if !values.isEmpty {
        diagnose("\(constructor.rawValue) takes no arguments", at: location)
        values.forEach { _ = resolve($0.1) }
      }
      return .layoutOperation(constructor)
    }
    let labels = values.map(\.0)
    let takesWidth = constructor == .wrap && labels.equal([.width, nil])
    guard labels == [nil] || takesWidth,
          let body = values.last?.1
    else {
      diagnose("\(constructor.rawValue) takes one layout closure", at: location)
      values.forEach { _ = resolve($0.1) }
      return constructor == .sourceLayout ? .sourceLayout :
        .layoutOperation(constructor)
    }
    if takesWidth {
      let width = resolve(values[0].1, expected: .optional(.integer))
      require(
        width,
        toMatch: .optional(.integer),
        subject: "the width",
        at: location
      )
    }
    resolveLayoutClosure(body)
    return constructor == .sourceLayout ? .sourceLayout :
      .layoutOperation(constructor)
  }

  mutating func resolveLayoutReplacement(
    receiver: RuntimeType,
    values: [(String?, RuntimeExpression)],
    at location: DeclarationLocation
  ) -> RuntimeType {
    if !receiver.collectionElement.providesSource {
      diagnose(
        "SourceLayout must replace a collection of captured source",
        at: location
      )
    }
    if let body = values.first?.1 { resolveLayoutClosure(body) }
    return .sourceEdit
  }

  private mutating func resolveLayoutClosure(_ expression: RuntimeExpression) {
    let canThrow: Bool
    if case let .closure(body) = expression.kind {
      canThrow =
        resolve(
          body, parameters: [], expectedResult: .sourceLayout,
          requiresSynchronousBody: true, allowsThrowingBody: true,
          builder: .layout
        ).isThrowing
    } else {
      let callable = resolve(expression)
      let parameters: [RuntimeType]
      let result: RuntimeType
      let isAsync: Bool
      switch callable {
      case let .function(function):
        parameters = function.parameters.map(\.type)
        result = function.result
        isAsync = function.isAsync
        canThrow = function.isThrowing
      case let .closure(closure):
        parameters = closure.parameters
        result = closure.result
        isAsync = closure.isAsync
        canThrow = closure.isThrowing
      default:
        diagnose(
          "SourceLayout takes a layout closure or function",
          at: expression.location
        )
        return
      }
      if !parameters.isEmpty || isAsync {
        diagnose(
          "SourceLayout takes a synchronous closure with no parameters",
          at: expression.location
        )
      }
      require(
        result,
        toMatch: .sourceLayout,
        subject: "the layout",
        at: expression.location
      )
    }
    requireEffects(
      canSuspend: false,
      canThrow: canThrow,
      at: expression.location
    )
  }
}
