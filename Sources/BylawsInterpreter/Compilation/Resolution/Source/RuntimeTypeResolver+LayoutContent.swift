import BylawsSemantics

extension RuntimeTypeResolver {
  func layoutContentCase(
    _ member: SupportedAPI.MemberLiteral, element: RuntimeType
  ) -> RuntimeType? {
    guard member.owners.contains(.layoutContent),
          let name = SupportedAPI.Member(rawValue: member.rawValue),
          let api = SupportedAPI.runtimeMethod(
            named: name,
            on: .staticType("LayoutContent")
          ),
          case let .method(call) = api.kind else { return nil }
    return .boundMethod(
      receiver: .constructor(.layoutContent, [element]),
      call: call,
      canSuspend: false,
      canThrow: false
    )
  }

  mutating func resolveLayoutContent(
    _ method: SupportedAPI.Method, types: [RuntimeType],
    values: [(String?, RuntimeExpression)], at location: DeclarationLocation
  ) -> RuntimeType {
    let element = types.first ?? layoutElementType ?? .unknown
    let result = RuntimeType.layoutContent(element)
    let outer = layoutElementType
    layoutElementType = element
    defer { layoutElementType = outer }
    let expected: RuntimeType = switch method {
    case .layout: .sourceLayout
    case .group: .layoutGroup(element)
    case .sequence: .array(result)
    case .separator: .staticMember([.sourceWhitespace])
    case .newline: .conditionalLayoutOperation(.newline, element)
    case .blankLine: .conditionalLayoutOperation(.blankLine, element)
    default: .unknown
    }
    guard values.count == 1, values[0].0 == nil else {
      diagnose("LayoutContent.\(method.rawValue) takes one value", at: location)
      values.forEach { _ = resolve($0.1) }
      return result
    }
    let type = resolve(values[0].1, expected: expected)
    if method != .layout || !type.providesLayout {
      require(
        type,
        toMatch: expected,
        subject: "the layout component",
        at: location
      )
    }
    return result
  }
}
