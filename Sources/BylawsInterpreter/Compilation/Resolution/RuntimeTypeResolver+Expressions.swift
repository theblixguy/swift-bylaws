import BylawsSemantics

extension RuntimeTypeResolver {
  mutating func resolve(
    _ expression: RuntimeExpression,
    expected: RuntimeType? = nil
  ) -> RuntimeType {
    let contextualType: RuntimeType? = if case .nilLiteral = expression.kind {
      expected
    } else if case let .optional(wrapped) = expected {
      wrapped
    } else {
      expected
    }
    switch expression.kind {
    case let .subscriptCall(base, key):
      let receiver = resolve(base)
      return resolveSubscript(
        receiver: receiver,
        key: key,
        at: expression.location
      )
    case let .array(elements):
      let expectedElement: RuntimeType? = if case let .array(element) =
        contextualType
      {
        element
      } else {
        nil
      }
      let elementTypes = elements.map { resolve($0, expected: expectedElement) }
      return .array(elementTypes
        .isEmpty ? expectedElement ?? .unknown : commonType(in: elementTypes))
    case .boolean: return .boolean
    case .integer: return contextualType == .double ? .double : .integer
    case .double: return .double
    case let .constructor(constructor): return .constructor(constructor, [])
    case .implicitConstructor:
      diagnose(
        "Initialiser must have a contextual type. Write the type name before its arguments.",
        at: expression.location
      )
      return .unknown
    case .string, .interpolatedString: return .string
    case .nilLiteral:
      if case let .optional(wrapped) = expected { return .optional(wrapped) }
      return .optional(.unknown)
    case let .reference(name):
      if let type = environment[name] { return type }
      if let constructor = SupportedAPI.Constructor(rawValue: name) {
        return .constructor(constructor, [])
      }
      if SupportedAPI.runtimeTypeNames.contains(name) {
        return .staticType(name)
      }
      diagnose("'\(name)' is not declared", at: expression.location)
      return .unknown
    case let .staticMember(literal):
      if case let .matcher(id) = literal,
         let matcher = SupportedAPI.matcher(named: id.rawValue)
      {
        return matcher.arguments == .none
          ? .matcher(matcher.singleModelType)
          : .prebuiltMatcher(id.rawValue)
      }
      return .staticMember(literal.owners)
    case let .generic(base, types):
      let resolved = resolve(base)
      switch resolved {
      case let .constructor(constructor, _):
        return .constructor(constructor, types)
      case let .staticType(name):
        guard let constructor = SupportedAPI.Constructor(rawValue: name) else {
          diagnose(
            "'\(name)' cannot take generic arguments",
            at: expression.location
          )
          return .unknown
        }
        return .constructor(constructor, types)
      default:
        diagnose(
          "this value cannot take generic arguments",
          at: expression.location
        )
        return .unknown
      }
    case let .member(base, name):
      let baseType = resolve(base)
      return resolveMember(name, of: baseType, at: expression.location)
    case let .call(callee, arguments, trailingClosure):
      let callable: RuntimeType
      if case .implicitConstructor = callee.kind,
         let constructor = contextualType.flatMap({
           SupportedAPI.Constructor(rawValue: $0.writtenName)
         })
      {
        constructors[callee.location] = constructor
        callable = .constructor(constructor, [])
      } else {
        callable = resolveCallable(callee)
      }
      return resolveCall(
        callable,
        arguments: arguments,
        trailingClosure: trailingClosure,
        name: callee.callableName,
        at: expression.location
      )
    case let .closure(closure):
      let expectedClosure: SupportedAPI.RuntimeClosureType? =
        if case let .closure(type) = contextualType { type } else { nil }
      return .closure(
        resolve(
          closure,
          parameters: expectedClosure?.parameters ?? [],
          expectedResult: expectedClosure?.result,
          requiresSynchronousBody: false
        )
      )
    case let .keyPath(members): return .keyPath(members)
    case let .prefix(operatorName, operand):
      let type = resolve(operand, expected: contextualType)
      switch (operatorName, type) {
      case ("!", .boolean): return .boolean
      case ("!", .matcher): return type
      case ("-", .integer): return .integer
      case ("-", .double): return .double
      default:
        diagnose(
          "'\(operatorName)' does not apply to \(type.writtenName)",
          at: expression.location
        )
        return .unknown
      }
    case let .binary(left, operatorName, right):
      return resolveBinary(
        operatorName,
        left: left,
        right: right,
        expected: contextualType,
        at: expression.location
      )
    }
  }

  mutating func resolveCallable(
    _ expression: RuntimeExpression
  ) -> RuntimeType {
    guard case let .member(base, name) = expression.kind else {
      return resolve(expression)
    }
    let baseType = resolve(base)
    if case let .optional(wrapped) = baseType {
      return (resolveMethod(name, of: wrapped) ?? resolveMember(
        name,
        of: wrapped,
        at: expression.location
      )).optionalChained
    }
    return resolveMethod(name, of: baseType)
      ?? resolveMember(name, of: baseType, at: expression.location)
  }

  func resolveMethod(
    _ name: SupportedAPI.Member,
    of type: RuntimeType
  ) -> RuntimeType? {
    guard let receiver = type.receiver,
          let api = SupportedAPI.runtimeMethod(named: name, on: receiver),
          case let .method(call) = api.kind
    else { return nil }
    return .boundMethod(
      receiver: type,
      call: call,
      canSuspend: api.canSuspend
    )
  }

  mutating func resolveMember(
    _ name: SupportedAPI.Member,
    of type: RuntimeType,
    at location: DeclarationLocation
  ) -> RuntimeType {
    if case let .optional(wrapped) = type {
      return resolveMember(name, of: wrapped, at: location).optionalChained
    }
    if case let .staticType(typeName) = type {
      if name == .selfType { return type }
      if typeName == SupportedAPI.ModelType.indexSymbol.rawValue,
         name == .kindType
      {
        return .staticType(SupportedAPI.StaticMemberType.indexSymbolKind
          .rawValue)
      }
      guard let owner = SupportedAPI.StaticMemberType(rawValue: typeName)?.owner
      else { return .unknown }
      return .staticMember([owner])
    }
    guard let receiver = type.receiver else {
      if type != .unknown {
        diagnose(
          "'\(name.rawValue)' is not a supported member of \(type.writtenName)",
          at: location
        )
      }
      return .unknown
    }
    guard let api = SupportedAPI.runtimeProperty(named: name, on: receiver)
      ?? SupportedAPI.runtimeMethod(named: name, on: receiver)
    else {
      diagnose(
        "'\(name.rawValue)' is not a supported member of \(type.receiverName)",
        at: location
      )
      return .unknown
    }
    switch api.kind {
    case let .property(result):
      if api.canSuspend, synchronousClosureDepth > 0 {
        diagnose("a synchronous closure cannot suspend", at: location)
      }
      return result.resolve(receiver: type, closureResult: nil)
    case let .method(call):
      return .boundMethod(
        receiver: type,
        call: call,
        canSuspend: api.canSuspend
      )
    }
  }
}
