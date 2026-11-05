import BylawsSemantics

extension RuntimeTypeResolver {
  mutating func resolveReplacementConstructor(
    _ constructor: SupportedAPI.Constructor,
    typeArguments: [RuntimeType],
    values: [(String?, RuntimeExpression)],
    at location: DeclarationLocation
  ) -> RuntimeType {
    if !typeArguments.isEmpty {
      diagnose(
        "\(constructor.rawValue) takes no generic arguments",
        at: location
      )
    }
    let result: RuntimeType = switch constructor {
    case .scope: .sourceScope
    case .sourceReplacement: .sourceReplacement
    default: .sourceCorrection
    }
    if constructor == .replace || constructor == .unwrap {
      requireEffects(canSuspend: false, canThrow: true, at: location)
    }
    let labels = values.map(\.0)
    if let argument = values.last, argument.0 != nil,
       case .closure = argument.1.kind
    {
      diagnose(
        "\(constructor.rawValue) takes an unlabelled content closure",
        at: argument.1.location
      )
    }
    if constructor == .unwrap {
      guard labels == [nil] || labels.equal([nil, .containingOnly]) else {
        diagnose(
          "Unwrap takes a source value and an optional content kind",
          at: location,
          resolvingArguments: values
        )
        return result
      }
      let target = resolve(values[0].1)
      let source = if case let .optional(wrapped) = target { wrapped }
      else { target }
      if !source.providesSource {
        diagnose("Unwrap takes captured source", at: values[0].1.location)
      }
      if values.count == 2 {
        let kind = RuntimeType.optional(.staticMember([.sourceNodeKind]))
        require(
          resolve(values[1].1, expected: kind),
          toMatch: kind,
          subject: "the content kind",
          at: values[1].1.location
        )
      }
      return result
    }
    if constructor == .replace {
      guard labels.equal([nil, .with]) || labels == [nil, nil] else {
        diagnose(
          "Replace takes a target and replacement content",
          at: location,
          resolvingArguments: values
        )
        return result
      }
      let target = resolve(values[0].1)
      if !target.providesSource {
        diagnose(
          "Replace takes a captured source target",
          at: values[0].1.location
        )
      }
      let content = resolveReplacementContent(values[1].1)
      if labels[1] == nil {
        if case .closure = values[1].1.kind {} else {
          diagnose(
            "Replace takes replacement content after with:",
            at: values[1].1.location
          )
        }
      } else if content.isAssignable(to: .staticMember([.sourceWhitespace])),
                target != .sourceSlice
      {
        diagnose(
          "Replace takes a SourceSlice for whitespace replacement",
          at: values[0].1.location
        )
      }
      if !content.providesSource, content != .sourceReplacement,
         content != .string,
         !content.isAssignable(to: .staticMember([.sourceWhitespace]))
      {
        diagnose(
          "Replace takes text, whitespace or captured syntax",
          at: values[1].1.location
        )
      }
      return result
    }
    let allowed: Bool = if constructor == .scope {
      labels == [nil] || labels.equal([.replacement])
    } else {
      labels == [nil] || labels.equal([.source]) || labels.equal([.sources])
        || labels.equal([.combining])
    }
    guard allowed else {
      diagnose(
        "\(constructor.rawValue) takes replacement content",
        at: location,
        resolvingArguments: values
      )
      return result
    }
    let content = resolveReplacementContent(values[0].1)
    let supported = if labels.equal([.source]) {
      content.providesSource
    } else if labels.equal([.sources]) {
      content.sequenceElement?.providesSource == true
    } else if labels.equal([.combining]) {
      content.sequenceElement == .sourceReplacement
    } else if labels.equal([.replacement]) {
      content == .sourceReplacement
    } else {
      content == .sourceReplacement
    }
    if labels == [nil] {
      if case .closure = values[0].1.kind {} else {
        diagnose(
          "\(constructor.rawValue) takes a trailing content closure",
          at: values[0].1.location
        )
      }
    }
    if !supported {
      diagnose(
        RuntimeBuilder.replacement.argumentRequirement,
        at: values[0].1.location
      )
    }
    return result
  }

  private mutating func resolveReplacementContent(
    _ expression: RuntimeExpression
  )
    -> RuntimeType
  {
    if case let .closure(body) = expression.kind {
      requireEffects(
        canSuspend: false,
        canThrow: body.usesTry,
        at: expression.location
      )
      return resolve(
        body,
        parameters: [],
        expectedResult: nil,
        requiresSynchronousBody: true,
        allowsThrowingBody: true,
        builder: .replacement
      )
      .result
    }
    return resolve(expression)
  }
}
