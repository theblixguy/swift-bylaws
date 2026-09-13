import BylawsSemantics

struct RuntimeTypeResolver {
  typealias RuntimeType = SupportedAPI.RuntimeType
  typealias RuntimeParameter = SupportedAPI.RuntimeParameter

  var environment: [String: RuntimeType]
  var diagnostics: [Diagnostic] = []
  var constructors: [DeclarationLocation: SupportedAPI.Constructor] = [:]
  let reportsDiagnostics: Bool
  var synchronousClosureDepth = 0

  init(
    environment: [String: RuntimeType],
    reportsDiagnostics: Bool = true
  ) {
    self.environment = environment
    self.reportsDiagnostics = reportsDiagnostics
  }

  mutating func resolve(_ function: RuntimeFunctionDefinition) {
    var functionEnvironment = environment
    for parameter in function.parameters {
      functionEnvironment[parameter.localName] = parameter.type
    }
    let expected = function.returnType
    let resolution = withEnvironment(functionEnvironment) { resolver in
      resolver.resolveBody(function.body, expected: expected)
    }
    if let result = resolution.resultTypes.first(where: {
      !$0.isAssignable(to: expected)
    }) {
      diagnose(
        "'\(function.name)' must return \(expected.writtenName), not \(result.writtenName)",
        at: function.location
      )
    }
  }

  mutating func resolve(
    _ closure: RuntimeClosureDefinition,
    parameters: [RuntimeType],
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
    let names = closure.parameters.isEmpty
      ? parameters.indices.map { "$\($0)" }
      : closure.parameters
    if !parameters.isEmpty, names.count != parameters.count {
      diagnose(
        "the closure takes \(argumentCountDescription(names.count)), not \(parameters.count)",
        at: closure.location
      )
    }
    var closureEnvironment = environment
    for (name, type) in zip(names, parameters) {
      closureEnvironment[name] = type
    }
    let resolution = withEnvironment(
      closureEnvironment,
      synchronousClosure: requiresSynchronousBody
    ) { resolver in
      resolver.resolveBody(
        closure.body, expected: expectedResult,
        builder: closure.body.containsReturn ? nil : builder
      )
    }
    let result = commonType(in: resolution.resultTypes)
    if let expectedResult {
      for result in resolution.resultTypes {
        require(
          result,
          toMatch: expectedResult,
          subject: "the closure",
          at: closure.location
        )
      }
    }
    return SupportedAPI.RuntimeClosureType(
      parameters: parameters,
      result: result,
      isAsync: closure.usesAwait,
      isThrowing: closure.usesTry
    )
  }

  mutating func resolve(
    _ body: RuntimeBody,
    expected: RuntimeType? = nil
  ) -> RuntimeType {
    commonType(in: resolveBody(body, expected: expected).resultTypes)
  }

  mutating func withEnvironment<Result>(
    _ environment: [String: RuntimeType],
    synchronousClosure: Bool? = nil,
    operation: (inout Self) -> Result
  ) -> Result {
    let outerEnvironment = self.environment
    let outerSynchronousClosureDepth = synchronousClosureDepth
    self.environment = environment
    if let synchronousClosure {
      synchronousClosureDepth = synchronousClosure ? synchronousClosureDepth +
        1 : 0
    }
    defer {
      self.environment = outerEnvironment
      synchronousClosureDepth = outerSynchronousClosureDepth
    }
    return operation(&self)
  }

  mutating func resolve(
    _ condition: RuntimeCondition
  ) -> (name: String, type: RuntimeType)? {
    switch condition {
    case let .boolean(expression):
      require(
        resolve(expression),
        toMatch: .boolean,
        subject: "the condition",
        at: expression.location
      )
      return nil
    case let .optionalBinding(name, expression):
      let type = resolve(expression)
      guard case let .optional(wrapped) = type else {
        diagnose(
          "an optional binding takes an Optional value, not \(type.writtenName)",
          at: expression.location
        )
        return nil
      }
      return (name, wrapped)
    }
  }

  mutating func resolveBinary(
    _ operatorName: String,
    left: RuntimeExpression,
    right: RuntimeExpression,
    expected: RuntimeType?,
    at location: DeclarationLocation
  ) -> RuntimeType {
    let numericExpectation = expected == .double ? RuntimeType.double : nil
    let leftExpectation = if operatorName == "+", case .array = expected {
      expected
    } else { numericExpectation }
    var leftType = resolve(left, expected: leftExpectation)
    if operatorName == "??", case let .optional(wrapped) = leftType {
      let rightType = resolve(right, expected: wrapped)
      require(
        rightType,
        toMatch: wrapped,
        subject: "the default value",
        at: right.location
      )
      return wrapped
    }
    let rightExpectation: RuntimeType? = if operatorName == "+",
                                            case .array = leftType
    {
      leftType
    } else { leftType == .double ? .double : nil }
    var rightType = resolve(right, expected: rightExpectation)
    switch (leftType, rightType) {
    case (.integer, .double) where left.isContextualIntegerLiteral:
      leftType = .double
    case (.double, .integer) where right.isContextualIntegerLiteral:
      rightType = .double
    default:
      break
    }
    switch operatorName {
    case "==", "!=":
      if case .nilLiteral = left.kind,
         case .optional = rightType { return .boolean }
      if case .nilLiteral = right.kind,
         case .optional = leftType { return .boolean }
      guard leftType.supportsEquality, rightType.supportsEquality else {
        diagnose(
          "'\(operatorName)' cannot compare \(leftType.writtenName) and \(rightType.writtenName)",
          at: location
        )
        return .boolean
      }
      guard leftType.isAssignable(to: rightType)
        || rightType.isAssignable(to: leftType)
      else {
        diagnose(
          "'\(operatorName)' does not apply to these values",
          at: location
        )
        return .boolean
      }
      return .boolean
    case "&&", "||":
      if case .matcher = leftType, case .matcher = rightType {
        let result = commonType(in: [leftType, rightType])
        if result == .unknown {
          diagnose(
            "'\(operatorName)' cannot combine \(leftType.writtenName) and \(rightType.writtenName)",
            at: location
          )
        }
        return result
      }
      require(
        leftType,
        toMatch: .boolean,
        subject: "the left operand",
        at: left.location
      )
      require(
        rightType,
        toMatch: .boolean,
        subject: "the right operand",
        at: right.location
      )
      return .boolean
    case "<", "<=", ">", ">=":
      guard leftType.isComparable, leftType == rightType else {
        diagnose(
          "'\(operatorName)' does not apply to these values",
          at: location
        )
        return .boolean
      }
      return .boolean
    case "+":
      if case .array = leftType, case .array = rightType,
         leftType.isAssignable(to: rightType) || rightType
         .isAssignable(to: leftType)
      {
        return leftType.containsUnknown ? rightType : leftType
      }
      guard leftType == rightType, leftType.supportsAddition else {
        diagnose("'+' does not apply to these values", at: location)
        return .unknown
      }
      return leftType
    default:
      diagnose(
        "portable rules do not support the '\(operatorName)' operator",
        at: location
      )
      return .unknown
    }
  }

  mutating func require(
    _ actual: RuntimeType,
    toMatch expected: RuntimeType,
    subject: String,
    at location: DeclarationLocation
  ) {
    guard !actual.isAssignable(to: expected) else { return }
    diagnose(
      "\(subject) must be \(expected.writtenName), not \(actual.writtenName)",
      at: location
    )
  }

  mutating func requireMatcher(
    _ type: RuntimeType,
    subject: SupportedAPI.ModelType,
    at location: DeclarationLocation
  ) {
    switch type {
    case .matcher(nil), .matcher(.some(subject)): return
    case let .matcher(actual):
      diagnose(
        "Matcher<\(actual?.rawValue ?? "unknown")> does not apply to \(subject.rawValue)",
        at: location
      )
    case .unknown: return
    default:
      diagnose("this value is not a Matcher", at: location)
    }
  }

  func commonType(in types: [RuntimeType]) -> RuntimeType {
    guard var result = types.first else { return .unknown }
    for type in types.dropFirst() {
      if result == .unknown { result = type }
      else if type == .unknown || type.isAssignable(to: result) { continue }
      else if result.isAssignable(to: type) { result = type }
      else { return .unknown }
    }
    return result
  }

  mutating func diagnose(
    _ message: String,
    at location: DeclarationLocation
  ) {
    guard reportsDiagnostics else { return }
    diagnostics.append(
      .error(message, at: location)
    )
  }
}
