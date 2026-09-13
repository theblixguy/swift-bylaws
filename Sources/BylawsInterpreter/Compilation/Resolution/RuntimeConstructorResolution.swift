import BylawsSemantics

struct RuntimeConstructorResolution {
  let constructors: [DeclarationLocation: SupportedAPI.Constructor]

  func resolve(_ expression: RuntimeExpression) -> RuntimeExpression {
    let kind: RuntimeExpression.Kind = switch expression.kind {
    case .implicitConstructor:
      constructors[expression.location].map(RuntimeExpression.Kind.constructor)
        ?? expression.kind
    case let .array(elements): .array(elements.map(resolve))
    case let .subscriptCall(base, key):
      .subscriptCall(base: resolve(base), key: resolve(key))
    case let .call(callee, arguments, closure):
      .call(
        callee: resolve(callee),
        arguments: arguments.map { .init(
          label: $0.label,
          value: resolve($0.value)
        ) },
        trailingClosure: closure.map(resolve)
      )
    case let .closure(closure): .closure(resolve(closure))
    case let .generic(base, arguments): .generic(
        base: resolve(base),
        arguments: arguments
      )
    case let .member(base, name): .member(base: resolve(base), name: name)
    case let .prefix(op, value): .prefix(operator: op, resolve(value))
    case let .binary(left, op, right): .binary(
        left: resolve(left),
        operator: op,
        right: resolve(right)
      )
    case let .interpolatedString(segments):
      .interpolatedString(segments.map { segment in
        switch segment {
        case .text: segment
        case let .expression(value): .expression(resolve(value))
        }
      })
    case .boolean, .constructor, .double, .integer, .keyPath, .nilLiteral,
         .reference,
         .staticMember, .string: expression.kind
    }
    return RuntimeExpression(kind: kind, location: expression.location)
  }

  func resolve(_ body: RuntimeBody) -> RuntimeBody {
    RuntimeBody(statements: body.statements.map { statement in
      let kind: RuntimeStatement.Kind = switch statement.kind {
      case let .binding(name, type, value): .binding(
          name: name,
          type: type,
          value: resolve(value)
        )
      case let .expression(value): .expression(resolve(value))
      case let .return(value): .return(value.map(resolve))
      case let .forStatement(name, sequence, body):
        .forStatement(
          name: name,
          sequence: resolve(sequence),
          body: resolve(body)
        )
      case let .guardStatement(condition, failure):
        .guardStatement(
          condition: resolve(condition),
          failure: resolve(failure)
        )
      case let .ifStatement(condition, success, failure):
        .ifStatement(
          condition: resolve(condition),
          success: resolve(success),
          failure: failure.map(resolve)
        )
      }
      return RuntimeStatement(kind: kind, location: statement.location)
    })
  }

  private func resolve(_ closure: RuntimeClosureDefinition)
    -> RuntimeClosureDefinition
  {
    RuntimeClosureDefinition(
      parameters: closure.parameters, body: resolve(closure.body),
      location: closure.location, usesAwait: closure.usesAwait,
      usesTry: closure.usesTry
    )
  }

  private func resolve(_ condition: RuntimeCondition) -> RuntimeCondition {
    switch condition {
    case let .boolean(value): .boolean(resolve(value))
    case let .optionalBinding(name, value): .optionalBinding(
        name: name,
        value: resolve(value)
      )
    }
  }
}
