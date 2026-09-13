import BylawsCore
import BylawsSemantics

struct RuntimeBody: Sendable {
  let statements: [RuntimeStatement]

  var containsReturn: Bool {
    statements.contains { statement in
      switch statement.kind {
      case .return: true
      case let .ifStatement(_, success, failure): success
        .containsReturn || failure?.containsReturn == true
      case let .guardStatement(_, failure): failure.containsReturn
      case let .forStatement(_, _, body): body.containsReturn
      default: false
      }
    }
  }
}

struct RuntimeStatement: Sendable {
  enum Kind: Sendable {
    case binding(
      name: String,
      type: SupportedAPI.RuntimeType?,
      value: RuntimeExpression
    )
    case expression(RuntimeExpression)
    case forStatement(
      name: String,
      sequence: RuntimeExpression,
      body: RuntimeBody
    )
    case guardStatement(condition: RuntimeCondition, failure: RuntimeBody)
    case ifStatement(
      condition: RuntimeCondition,
      success: RuntimeBody,
      failure: RuntimeBody?
    )
    case `return`(RuntimeExpression?)
  }

  let kind: Kind
  let location: DeclarationLocation
}

enum RuntimeCondition: Sendable {
  case boolean(RuntimeExpression)
  case optionalBinding(name: String, value: RuntimeExpression)
}
