import BylawsSemantics

extension RuntimeEvaluator {
  func expressionMember(
    _ name: SupportedAPI.Member,
    _ value: SourceExpression
  ) -> RuntimeValue? {
    switch name {
    case .name: .string(value.name)
    case .text: .string(value.text)
    case .compilationBranches: modelArray(
        value.compilationBranches,
        RuntimeModelValue.compilationBranch
      )
    case .enclosingDeclarations: modelArray(
        value.enclosingDeclarations,
        RuntimeModelValue.enclosingDeclaration
      )
    case .stringValue: optionalString(value.stringValue)
    case .integerValue: .optional(value.integerValue.map(RuntimeValue.integer))
    case .floatingPointValue: .optional(value.floatingPointValue
        .map(RuntimeValue.double))
    case .booleanValue: .optional(value.booleanValue.map(RuntimeValue.boolean))
    case .isNilLiteral: .boolean(value.isNilLiteral)
    case .referenceName: optionalString(value.referenceName)
    case .referenceLocation: optionalModel(value.referenceLocation) {
        .check(.location($0))
      }
    case .base: optionalModel(value.base, RuntimeModelValue.sourceExpression)
    case .calledExpression: optionalModel(
        value.calledExpression,
        RuntimeModelValue.sourceExpression
      )
    case .arrayElements:
      .optional(value.arrayElements.map { modelArray(
        $0,
        RuntimeModelValue.sourceExpression
      ) })
    case .dictionaryElements:
      .optional(value.dictionaryElements.map { modelArray(
        $0,
        RuntimeModelValue.dictionaryElement
      ) })
    case .arguments:
      .optional(value.arguments.map { modelArray(
        $0,
        RuntimeModelValue.expressionArgument
      ) })
    case .interpolations:
      .array(value.interpolations.map { modelArray(
        $0,
        RuntimeModelValue.expressionArgument
      ) })
    default: nil
    }
  }

  func callArgumentMember(
    _ name: SupportedAPI.Member,
    _ value: FunctionCall.Argument
  ) -> RuntimeValue? {
    switch name {
    case .label: optionalString(value.label)
    case .text: .string(value.text)
    case .expression: optionalModel(
        value.expression,
        RuntimeModelValue.sourceExpression
      )
    case .location: optionalModel(value.location) { .check(.location($0)) }
    default: nil
    }
  }

  func expressionArgumentMember(
    _ name: SupportedAPI.Member,
    _ value: SourceExpression.Argument
  ) -> RuntimeValue? {
    switch name {
    case .label: optionalString(value.label)
    case .expression: .model(.sourceExpression(value.expression))
    default: nil
    }
  }

  func dictionaryElementMember(
    _ name: SupportedAPI.Member,
    _ value: SourceExpression.DictionaryElement
  ) -> RuntimeValue? {
    switch name {
    case .key: .model(.sourceExpression(value.key))
    case .value: .model(.sourceExpression(value.value))
    default: nil
    }
  }
}
