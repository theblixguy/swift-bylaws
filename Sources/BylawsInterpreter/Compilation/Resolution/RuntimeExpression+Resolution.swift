extension RuntimeExpression {
  static func closure(
    _ definition: RuntimeClosureDefinition
  ) -> RuntimeExpression {
    RuntimeExpression(kind: .closure(definition), location: definition.location)
  }

  var callableName: String? {
    switch kind {
    case let .member(_, name): name.rawValue
    case let .reference(name): name
    case let .staticMember(literal): literal.rawValue
    default: nil
    }
  }

  var isContextualIntegerLiteral: Bool {
    switch kind {
    case .integer: true
    case let .prefix("-", operand): operand.isContextualIntegerLiteral
    default: false
    }
  }
}
