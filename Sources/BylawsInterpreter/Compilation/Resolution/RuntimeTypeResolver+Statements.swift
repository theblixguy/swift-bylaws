extension RuntimeTypeResolver {
  mutating func resolveBody(
    _ body: RuntimeBody,
    expected: RuntimeType?,
    builder: RuntimeBuilder? = nil
  ) -> RuntimeBodyResolution {
    var results: [RuntimeType] = [.void]
    var returned: [RuntimeType] = []
    var alwaysReturns = false
    for statement in body.statements {
      var statementAlwaysReturns = false
      switch statement.kind {
      case let .binding(name, expected, expression):
        let type = resolve(expression, expected: expected)
        if let expected {
          require(
            type,
            toMatch: expected,
            subject: "'\(name)'",
            at: statement.location
          )
          environment[name] = expected
        } else {
          environment[name] = type
        }
        results = [.void]
      case let .expression(expression):
        let result = resolve(expression, expected: expected)
        results = [result]
        if builder == .layout {
          switch result {
          case let .layoutGroup(element), let .conditionalLayoutOperation(
            _,
            element
          ):
            layoutUsesAutomaticOperations = true
            if let layoutElementType {
              require(
                element,
                toMatch: layoutElementType,
                subject: "the layout element",
                at: expression.location
              )
            }
          default: break
          }
        }
        if let builder, !builder.accepts(result) {
          diagnose(
            builder.argumentRequirement,
            at: expression.location
          )
        }
      case let .forStatement(name, sequence, body):
        let type = resolve(sequence)
        guard let element = type.sequenceElement else {
          diagnose("for takes a sequence", at: sequence.location)
          continue
        }
        var iteration = environment
        iteration[name] = element
        let resolution = withEnvironment(iteration) { resolver in
          resolver.resolveBody(body, expected: expected, builder: builder)
        }
        returned.append(contentsOf: resolution.returnedTypes)
        results = [.void]
      case let .return(expression):
        let type = expression.map { resolve($0, expected: expected) } ?? .void
        returned.append(type)
        results = [type]
        statementAlwaysReturns = true
      case let .guardStatement(condition, failure):
        let outer = environment
        let bindings = resolve(condition)
        let failureResolution = withEnvironment(outer) { resolver in
          resolver.resolveBody(failure, expected: expected)
        }
        if !failureResolution.alwaysReturns {
          diagnose(
            "a guard failure must leave the current scope",
            at: statement.location
          )
        }
        for binding in bindings {
          environment[binding.name] = binding.type
        }
        returned.append(contentsOf: failureResolution.returnedTypes)
        results = [.void]
      case let .ifStatement(condition, success, failure):
        var successEnvironment = environment
        for binding in resolve(condition) {
          successEnvironment[binding.name] = binding.type
        }
        let outer = environment
        let successResolution =
          withEnvironment(successEnvironment) { resolver in
            resolver.resolveBody(success, expected: expected, builder: builder)
          }
        let failureResolution: RuntimeBodyResolution = if let failure {
          withEnvironment(outer) { resolver in
            resolver.resolveBody(failure, expected: expected, builder: builder)
          }
        } else {
          RuntimeBodyResolution(
            fallthroughTypes: [.void],
            returnedTypes: [],
            alwaysReturns: false
          )
        }
        returned.append(contentsOf: successResolution.returnedTypes)
        returned.append(contentsOf: failureResolution.returnedTypes)
        results = [successResolution, failureResolution]
          .filter { !$0.alwaysReturns }
          .flatMap(\.fallthroughTypes)
        statementAlwaysReturns = successResolution.alwaysReturns
          && failureResolution.alwaysReturns
      }
      if statementAlwaysReturns {
        alwaysReturns = true
        break
      }
    }
    return RuntimeBodyResolution(
      fallthroughTypes: builder.map { [$0.resultType] } ?? results,
      returnedTypes: returned,
      alwaysReturns: alwaysReturns
    )
  }
}

struct RuntimeBodyResolution {
  let fallthroughTypes: [SupportedAPI.RuntimeType]
  let returnedTypes: [SupportedAPI.RuntimeType]
  let alwaysReturns: Bool

  var resultTypes: [SupportedAPI.RuntimeType] {
    alwaysReturns ? returnedTypes : returnedTypes + fallthroughTypes
  }
}
