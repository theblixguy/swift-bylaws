import BylawsSemantics

extension RuntimeTypeResolver {
  mutating func resolveCall(
    _ callable: RuntimeType,
    arguments: [RuntimeCallArgument],
    trailingClosure: RuntimeClosureDefinition?,
    name: String?,
    at location: DeclarationLocation
  ) -> RuntimeType {
    let trailing: [(String?, RuntimeExpression)] = trailingClosure.map {
      [(nil, RuntimeExpression.closure($0))]
    } ?? []
    let values = arguments.map { ($0.label, $0.value) } + trailing
    switch callable {
    case let .boundMethod(receiver, call, canSuspend):
      guard call.arguments.accepts(labels: values.map(\.0)) else {
        diagnose(
          "'\(call.method.rawValue)' takes arguments \(call.arguments.rendered)",
          at: location
        )
        values.forEach { _ = resolve($0.1) }
        return call.result.resolve(receiver: receiver, closureResult: nil)
      }
      if canSuspend, synchronousClosureDepth > 0 {
        diagnose("a synchronous closure cannot suspend", at: location)
      }
      if case let .constructor(.matcher, types) = receiver {
        return resolveMemberMatcher(types: types, values: values, at: location)
      }
      let resolved = resolveArguments(
        values,
        for: call,
        receiver: receiver,
        at: location
      )
      return call.result.resolve(
        receiver: receiver,
        closureResult: resolved.last,
        argumentLabels: values.map(\.0)
      )
    case let .function(function):
      let labels = values.map(\.0)
      let expectedLabels = function.parameters.map(\.label)
      guard labels == expectedLabels else {
        diagnose(
          "'\(function.name)' takes arguments \(argumentLabelList(expectedLabels))",
          at: location
        )
        values.forEach { _ = resolve($0.1) }
        return function.result
      }
      if synchronousClosureDepth > 0,
         function.isAsync || function.isThrowing
      {
        diagnose(
          "a synchronous closure cannot call an async or throwing helper",
          at: location
        )
      }
      for (argument, parameter) in zip(values, function.parameters) {
        let type = resolve(argument.1, expected: parameter.type)
        require(
          type,
          toMatch: parameter.type,
          subject: "'\(parameter.label ?? "argument")'",
          at: argument.1.location
        )
      }
      return function.result
    case let .closure(closure):
      guard values.allSatisfy({ $0.0 == nil }),
            values.count == closure.parameters.count
      else {
        diagnose(
          "the closure arguments do not match its parameters",
          at: location
        )
        return closure.result
      }
      for (argument, parameter) in zip(values, closure.parameters) {
        let type = resolve(argument.1, expected: parameter)
        require(type, toMatch: parameter, subject: "the argument", at: location)
      }
      return closure.result
    case let .constructor(constructor, typeArguments):
      return resolveConstructor(
        constructor,
        typeArguments: typeArguments,
        values: values,
        at: location
      )
    case let .prebuiltMatcher(name):
      return resolvePrebuiltMatcher(name, values: values, at: location)
    case let .optional(wrapped):
      return resolveCall(
        wrapped,
        arguments: arguments,
        trailingClosure: trailingClosure,
        name: name,
        at: location
      ).optionalChained
    case .unknown:
      values.forEach { _ = resolve($0.1) }
      return .unknown
    default:
      values.forEach { _ = resolve($0.1) }
      diagnose(
        "'\(name ?? callable.writtenName)' is not callable",
        at: location
      )
      return .unknown
    }
  }

  mutating func resolveArguments(
    _ values: [(String?, RuntimeExpression)],
    for call: SupportedAPI.RuntimeCall,
    receiver: RuntimeType,
    at location: DeclarationLocation
  ) -> [RuntimeType] {
    let parameters = call.arguments.parameters(
      for: values.map(\.0),
      expressions: values.map(\.1)
    )
    let element = receiver.collectionElement
    return zip(values, parameters).enumerated().map { offset, pair in
      let (argument, parameter) = pair
      switch parameter.type {
      case .dictionaryValueCallable:
        guard case let .dictionary(_, valueType) = receiver
        else { return .unknown }
        return resolveCallable(
          argument.1,
          input: valueType,
          expectedResult: nil,
          at: location
        )
      case .any:
        return resolve(argument.1)
      case let .oneOf(types):
        let actual = resolve(argument.1, expected: types.last)
        if !types.contains(where: { actual.isAssignable(to: $0) }) {
          diagnose(
            "argument \(offset + 1) must be "
              + types.map(\.writtenName).joined(separator: " or "),
            at: argument.1.location
          )
        }
        return actual
      case let .exact(expected):
        let actual = resolve(argument.1, expected: expected)
        require(
          actual,
          toMatch: expected,
          subject: "argument \(offset + 1)",
          at: argument.1.location
        )
        return actual
      case .sequenceOfCollectionElement:
        let actual = resolve(argument.1, expected: .array(element))
        guard let actualElement = actual.sequenceElement else {
          diagnose("the argument must be a sequence", at: argument.1.location)
          return actual
        }
        require(
          actualElement,
          toMatch: element,
          subject: "the sequence element",
          at: argument.1.location
        )
        return actual
      case .collectionElement:
        if call.method == .contains, !element.supportsEquality {
          diagnose(
            "'contains' cannot compare \(element.writtenName) values",
            at: location
          )
        }
        let actual = resolve(argument.1, expected: element)
        require(
          actual,
          toMatch: element,
          subject: "argument \(offset + 1)",
          at: argument.1.location
        )
        return actual
      case .matcherForSelection, .selectionFilter:
        let actual = resolve(argument.1)
        if case let .keyPath(members) = actual {
          _ = resolveKeyPath(
            members,
            input: element,
            expectedResult: .boolean,
            at: argument.1.location
          )
        } else if case let .selection(family) = receiver,
                  let model = SupportedAPI.ModelType(declarationFamily: family)
        {
          requireMatcher(actual, subject: model, at: argument.1.location)
        }
        return actual
      case let .collectionCallable(expectedResult):
        return resolveCallable(
          argument.1,
          input: element,
          expectedResult: expectedResult,
          at: location
        )
      case let .callable(input, expectedResult):
        return resolveCallable(
          argument.1,
          input: input,
          expectedResult: expectedResult,
          at: location
        )
      }
    }
  }

  mutating func resolveCallable(
    _ expression: RuntimeExpression,
    input: RuntimeType,
    expectedResult: RuntimeType?,
    at location: DeclarationLocation
  ) -> RuntimeType {
    switch expression.kind {
    case let .closure(definition):
      return resolve(
        definition,
        parameters: [input],
        expectedResult: expectedResult,
        requiresSynchronousBody: true
      ).result
    case let .keyPath(members):
      return resolveKeyPath(
        members,
        input: input,
        expectedResult: expectedResult,
        at: expression.location
      )
    default:
      let type = resolve(expression)
      if case let .function(function) = type {
        if function.isAsync || function.isThrowing {
          diagnose(
            "the collection helper must be synchronous and nonthrowing",
            at: expression.location
          )
        }
        if function.parameters.count == 1 {
          require(
            input,
            toMatch: function.parameters[0].type,
            subject: "the collection element",
            at: expression.location
          )
        } else {
          diagnose(
            "the collection helper takes one parameter",
            at: expression.location
          )
        }
        if let expectedResult {
          require(
            function.result,
            toMatch: expectedResult,
            subject: "the helper result",
            at: expression.location
          )
        }
        return function.result
      }
      guard case let .closure(closure) = type else {
        diagnose(
          "this collection operation takes a closure, function or key path",
          at: location
        )
        return .unknown
      }
      if let expectedResult {
        require(
          closure.result,
          toMatch: expectedResult,
          subject: "the closure",
          at: expression.location
        )
      }
      return closure.result
    }
  }

  mutating func resolveKeyPath(
    _ members: [SupportedAPI.Member],
    input: RuntimeType,
    expectedResult: RuntimeType?,
    at location: DeclarationLocation
  ) -> RuntimeType {
    var result = input
    for member in members {
      result = resolveMember(member, of: result, at: location)
    }
    if let expectedResult {
      require(
        result,
        toMatch: expectedResult,
        subject: "the key path",
        at: location
      )
    }
    return result
  }
}
