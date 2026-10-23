import BylawsSemantics

extension RuntimeTypeResolver {
  mutating func resolveRuleBody(_ body: RuntimeClosureDefinition) {
    let result = resolve(
      body, parameters: [], expectedResult: nil,
      requiresSynchronousBody: false, builder: .checks
    ).result
    if !result.isRuleResult {
      diagnose(
        "Rule must return a check result, Violations or Rule.Findings",
        at: body.location
      )
    }
  }

  mutating func resolveFix(
    receiver: RuntimeType,
    values: [(String?, RuntimeExpression)],
    at location: DeclarationLocation
  ) -> RuntimeType {
    guard case let .violations(subject) = receiver,
          let expression = values.last?.1
    else { return receiver }
    if values.count == 2 {
      let title = resolve(values[0].1, expected: .optional(.string))
      require(
        title,
        toMatch: .optional(.string),
        subject: "the fix title",
        at: location
      )
    }
    let input = RuntimeType.fixContext(subject)
    resolveCorrectionBody(expression, input: input, at: location)
    return receiver
  }

  mutating func resolveCorrectionCheck(
    receiver: RuntimeType,
    values: [(String?, RuntimeExpression)],
    at location: DeclarationLocation
  ) -> RuntimeType {
    requireEffects(canSuspend: true, canThrow: true, at: location)
    require(
      resolve(values[0].1),
      toMatch: .string,
      subject: "the requirement",
      at: location
    )
    resolveCorrectionBody(
      values[1].1,
      input: receiver.collectionElement,
      at: location
    )
    return .violations(receiver.collectionElement.modelType)
  }

  mutating func resolveCorrectionBody(
    _ expression: RuntimeExpression,
    input: RuntimeType,
    at location: DeclarationLocation
  ) {
    if case let .closure(body) = expression.kind {
      _ = resolve(
        body, parameters: [input], expectedResult: .array(.sourceEdit),
        requiresSynchronousBody: false, builder: .edits
      )
      return
    }
    let callable = resolve(expression)
    let parameters: [RuntimeType]
    let result: RuntimeType
    let takesContext = if case .fixContext = input { true } else { false }
    switch callable {
    case let .function(function):
      parameters = function.parameters.map(\.type)
      result = function.result
    case let .closure(closure):
      parameters = closure.parameters
      result = closure.result
    default:
      diagnose(
        takesContext
          ? "withFix takes a fix closure or function"
          : "violations takes a correction closure or function",
        at: location
      )
      return
    }
    if parameters.count == 1 {
      require(
        input,
        toMatch: parameters[0],
        subject: takesContext ? "the fix context" : "the correction input",
        at: location
      )
    } else {
      diagnose(
        takesContext
          ? "the fix function takes one FixContext"
          : "the correction function takes one input parameter",
        at: location
      )
    }
    require(
      result,
      toMatch: .array(.sourceEdit),
      subject: takesContext ? "the fix result" : "the correction result",
      at: location
    )
  }

  mutating func resolveBuilder(
    _ values: [(String?, RuntimeExpression)],
    builder: RuntimeBuilder,
    at location: DeclarationLocation
  ) -> Bool {
    guard values.count == 1, values[0].0 == nil,
          case let .closure(body) = values[0].1.kind
    else { return false }
    let expected: RuntimeType = builder == .layers ? .array(.layer) :
      .array(.rule)
    let result = resolve(
      body,
      parameters: [],
      expectedResult: nil,
      requiresSynchronousBody: true,
      builder: builder
    ).result
    require(
      result,
      toMatch: body.body.containsReturn ? expected : builder.resultType,
      subject: "the builder",
      at: location
    )
    return true
  }

  mutating func resolveLayer(
    _ values: [(String?, RuntimeExpression)],
    at location: DeclarationLocation
  ) -> RuntimeType {
    let labels = values.map(\.0)
    let allowed = [
      "files",
      "modules",
      "mayImport",
      "mustImport",
      "mustNotImport",
    ]
    let order =
      labels
        .compactMap { label in label.flatMap { allowed.firstIndex(of: $0) } }
    guard labels.first == .some(nil),
          labels.dropFirst().allSatisfy({ $0.map(allowed.contains) == true }),
          Set(labels.compactMap(\.self)).count == labels.count - 1,
          order == order.sorted(),
          labels.contains("files")
    else {
      diagnose(
        "Layer takes one name, files, and optional import settings",
        at: location
      )
      return .layer
    }
    for (label, expression) in values {
      let expected: RuntimeType = label == nil ? .string : .array(.string)
      let type = resolve(expression, expected: expected)
      if label == "mayImport",
         type == .staticMember([.layerImportPolicy])
      {
        continue
      }
      require(
        type,
        toMatch: expected,
        subject: label ?? "the layer name",
        at: expression.location
      )
    }
    return .layer
  }
}
