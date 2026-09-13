import BylawsCore
import BylawsSemantics

struct RuntimeExpression: Sendable {
  indirect enum Kind: Sendable {
    case array([RuntimeExpression])
    case boolean(Bool)
    case call(
      callee: RuntimeExpression,
      arguments: [RuntimeCallArgument],
      trailingClosure: RuntimeClosureDefinition?
    )
    case closure(RuntimeClosureDefinition)
    case double(Double)
    case generic(base: RuntimeExpression, arguments: [SupportedAPI.RuntimeType])
    case integer(Int)
    case implicitConstructor
    case constructor(SupportedAPI.Constructor)
    case interpolatedString([RuntimeStringSegment])
    case keyPath([SupportedAPI.Member])
    case member(base: RuntimeExpression, name: SupportedAPI.Member)
    case subscriptCall(base: RuntimeExpression, key: RuntimeExpression)
    case nilLiteral
    case prefix(operator: String, RuntimeExpression)
    case binary(
      left: RuntimeExpression,
      operator: String,
      right: RuntimeExpression
    )
    case reference(String)
    case staticMember(SupportedAPI.MemberLiteral)
    case string(String)
  }

  let kind: Kind
  let location: DeclarationLocation
}

struct RuntimeCallArgument: Sendable {
  let label: String?
  let value: RuntimeExpression
}

enum RuntimeStringSegment: Sendable {
  case text(String)
  case expression(RuntimeExpression)
}
