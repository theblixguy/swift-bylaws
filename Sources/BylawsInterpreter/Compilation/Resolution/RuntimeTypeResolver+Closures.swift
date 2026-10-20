import BylawsSemantics

extension RuntimeTypeResolver {
  mutating func resolve(
    _ closure: RuntimeClosureDefinition,
    parameters contextualParameters: [RuntimeType]?,
    expectedResult: RuntimeType?,
    requiresSynchronousBody: Bool,
    builder: RuntimeBuilder? = nil
  ) -> SupportedAPI.RuntimeClosureType {
    if requiresSynchronousBody, closure.usesAwait || closure.usesTry {
      diagnose(
        "this closure must be synchronous and nonthrowing",
        at: closure.location
      )
    }
    let parameters: [(name: String, type: RuntimeType)]
    if let written = closure.parameters {
      if let contextualParameters, written.count != contextualParameters.count {
        diagnose(
          "the closure takes \(argumentCountDescription(written.count)), not \(contextualParameters.count)",
          at: closure.location
        )
      }
      parameters = written.enumerated().map { index, parameter in
        let contextual = contextualParameters.flatMap {
          $0.indices.contains(index) ? $0[index] : nil
        }
        if let annotation = parameter.type, let contextual {
          require(
            contextual, toMatch: annotation,
            subject: "the closure parameter", at: closure.location
          )
        }
        let type = parameter.type ?? contextual ?? .unknown
        if type == .unknown {
          diagnose(
            "the closure parameter must have a type. Add its type annotation.",
            at: closure.location
          )
        }
        return (parameter.name, type)
      }
    } else {
      parameters = (contextualParameters ?? []).enumerated().map {
        ("$\($0.offset)", $0.element)
      }
    }
    var closureEnvironment = environment
    for parameter in parameters {
      closureEnvironment[parameter.name] = parameter.type
    }
    let outerSuspension = observedSuspension
    let outerThrowing = observedThrowing
    observedSuspension = false
    observedThrowing = false
    defer {
      observedSuspension = outerSuspension
      observedThrowing = outerThrowing
    }
    let resolution = withEnvironment(
      closureEnvironment,
      synchronousClosure: requiresSynchronousBody,
      allowsThrowing: !requiresSynchronousBody,
      allowsSuspension: !requiresSynchronousBody
    ) { resolver in
      resolver.resolveBody(
        closure.body, expected: closure.resultType ?? expectedResult,
        builder: closure.body.containsReturn ? nil : builder
      )
    }
    if let expected = closure.resultType ?? expectedResult {
      for result in resolution.resultTypes {
        require(
          result, toMatch: expected,
          subject: "the closure", at: closure.location
        )
      }
    }
    let result = closure.resultType ?? commonType(in: resolution.resultTypes)
    if let writtenResult = closure.resultType, let expectedResult {
      require(
        writtenResult, toMatch: expectedResult,
        subject: "the closure", at: closure.location
      )
    }
    return SupportedAPI.RuntimeClosureType(
      parameters: parameters.map(\.type),
      result: result,
      isAsync: closure.usesAwait || observedSuspension,
      isThrowing: closure.usesTry || observedThrowing
    )
  }

  mutating func requireEffects(
    canSuspend: Bool, canThrow: Bool,
    at location: DeclarationLocation
  ) {
    observedSuspension = observedSuspension || canSuspend
    observedThrowing = observedThrowing || canThrow
    if canSuspend, !allowsSuspension {
      let message = if synchronousClosureDepth > 0 {
        "a synchronous closure cannot suspend"
      } else {
        "a synchronous body cannot call an async API. Use an async function or fix closure."
      }
      diagnose(message, at: location)
    }
    if canThrow, !allowsThrowing {
      diagnose(
        "a nonthrowing body cannot call a throwing API. Use a throwing function or fix closure.",
        at: location
      )
    }
  }
}
