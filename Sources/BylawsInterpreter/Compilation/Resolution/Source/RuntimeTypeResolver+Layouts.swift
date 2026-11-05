import BylawsSemantics

extension RuntimeTypeResolver {
  mutating func resolveLayoutConstructor(
    _ constructor: SupportedAPI.Constructor,
    values: [(String?, RuntimeExpression)],
    at location: DeclarationLocation
  ) -> RuntimeType {
    if constructor == .layout {
      return resolveLayoutOperation(values: values, at: location)
    }
    if constructor == .group {
      return resolveLayoutGroup(values: values, at: location)
    }
    if constructor == .newline || constructor == .blankLine || constructor ==
      .softBreak
    {
      if constructor != .softBreak, !values.isEmpty {
        let labels = values.map(\.0)
        guard labels.equal([.before]) || labels.equal([.after])
          || labels.equal([.between, .and])
        else {
          diagnose(
            "\(constructor.rawValue) takes one predicate with before: or after:, or two predicates with between:and:",
            at: location
          )
          values.forEach { _ = resolve($0.1) }
          return .conditionalLayoutOperation(
            constructor,
            layoutElementType ?? .unknown
          )
        }
        for (_, predicate) in values {
          resolveLayoutPredicate(predicate, at: location)
        }
        return .conditionalLayoutOperation(
          constructor,
          layoutElementType ?? .unknown
        )
      }
      if !values.isEmpty {
        diagnose("\(constructor.rawValue) takes no arguments", at: location)
        values.forEach { _ = resolve($0.1) }
      }
      return .layoutOperation(constructor)
    }
    return resolveLayoutComponent(constructor, values: values, at: location)
  }

  mutating func resolveLayoutReplacement(
    receiver: RuntimeType,
    values: [(String?, RuntimeExpression)],
    at location: DeclarationLocation
  ) -> RuntimeType {
    if let value = values.first(where: { $0.0 == "when" })?.1 {
      let condition = resolve(
        value,
        expected: .optional(.sourceLayoutCondition)
      )
      require(
        condition,
        toMatch: .optional(.sourceLayoutCondition),
        subject: "the condition",
        at: location
      )
    }
    if !receiver.collectionElement.providesSource {
      diagnose(
        "SourceLayout must replace a collection of captured source",
        at: location
      )
    }
    if values.first?.0 == "layout" {
      let layout = resolve(values[0].1, expected: .sourceLayout)
      if !layout.providesLayout { require(
        layout,
        toMatch: .sourceLayout,
        subject: "the layout",
        at: location
      ) }
      return .sourceEdit
    }
    let outerElement = layoutElementType
    layoutElementType = receiver.collectionElement
    defer {
      layoutElementType = outerElement
    }
    if let body = values.last?.1 { resolveLayoutClosure(
      body,
      builder: .sourceLayout
    ) }
    return .sourceEdit
  }

  private mutating func resolveLayoutPredicate(
    _ expression: RuntimeExpression,
    at location: DeclarationLocation
  ) {
    guard let element = layoutElementType else {
      diagnose(
        "Layout must contain grouping and spacing policies. Move the policy into Layout.",
        at: location
      )
      _ = resolve(expression)
      return
    }
    _ = resolveCallable(
      expression, input: element, expectedResult: .boolean,
      allowsThrowing: true, propagatesEffects: false, at: location
    )
  }

  mutating func resolveLayoutClosure(
    _ expression: RuntimeExpression, builder: RuntimeBuilder = .layout
  ) {
    let expected: RuntimeType = builder == .layout
      ? .layoutContent(layoutElementType ?? .unknown) : .sourceLayout
    let canThrow: Bool
    if case let .closure(body) = expression.kind {
      canThrow =
        resolve(
          body, parameters: [], expectedResult: expected,
          requiresSynchronousBody: true, allowsThrowingBody: true,
          builder: builder
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
        toMatch: expected,
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
