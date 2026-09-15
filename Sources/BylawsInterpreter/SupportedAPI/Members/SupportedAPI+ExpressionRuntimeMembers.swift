extension SupportedAPI {
  static let expressionRuntimeMembers: [RuntimeMemberAPI] = [
    property(
      .expressions,
      on: [.model(.sourceFile)],
      result: .fixed(.array(.model(.sourceExpression)))
    ),
    property(
      .arguments,
      on: [.model(.functionCall)],
      result: .fixed(.array(.model(.callArgument)))
    ),
    property(
      .label,
      on: [.model(.callArgument), .model(.expressionArgument)],
      result: .fixed(.optional(.string))
    ),
    property(
      .text,
      on: [.model(.callArgument), .model(.sourceExpression)],
      result: .fixed(.string)
    ),
    property(
      .expression,
      on: [.model(.callArgument)],
      result: .fixed(.optional(.model(.sourceExpression)))
    ),
    property(
      .location,
      on: [.model(.callArgument)],
      result: .fixed(.optional(.model(.declarationLocation)))
    ),
    property(
      .expression,
      on: [.model(.expressionArgument)],
      result: .fixed(.model(.sourceExpression))
    ),
    property(
      .key,
      on: [.model(.dictionaryElement)],
      result: .fixed(.model(.sourceExpression))
    ),
    property(
      .value,
      on: [.model(.dictionaryElement)],
      result: .fixed(.model(.sourceExpression))
    ),
    property(.name, on: [.model(.sourceExpression)], result: .fixed(.string)),
    property(
      .location,
      on: [.model(.sourceExpression)],
      result: .fixed(.model(.declarationLocation))
    ),
    property(
      .stringValue,
      on: [.model(.sourceExpression)],
      result: .fixed(.optional(.string))
    ),
    property(
      .integerValue,
      on: [.model(.sourceExpression)],
      result: .fixed(.optional(.integer))
    ),
    property(
      .floatingPointValue,
      on: [.model(.sourceExpression)],
      result: .fixed(.optional(.double))
    ),
    property(
      .booleanValue,
      on: [.model(.sourceExpression)],
      result: .fixed(.optional(.boolean))
    ),
    property(
      .isNilLiteral,
      on: [.model(.sourceExpression)],
      result: .fixed(.boolean)
    ),
    property(
      .referenceName,
      on: [.model(.sourceExpression)],
      result: .fixed(.optional(.string))
    ),
    property(
      .referenceLocation,
      on: [.model(.sourceExpression)],
      result: .fixed(.optional(.model(.declarationLocation)))
    ),
    property(
      .base,
      on: [.model(.sourceExpression)],
      result: .fixed(.optional(.model(.sourceExpression)))
    ),
    property(
      .calledExpression,
      on: [.model(.sourceExpression)],
      result: .fixed(.optional(.model(.sourceExpression)))
    ),
    property(
      .arrayElements,
      on: [.model(.sourceExpression)],
      result: .fixed(.optional(.array(.model(.sourceExpression))))
    ),
    property(
      .dictionaryElements,
      on: [.model(.sourceExpression)],
      result: .fixed(.optional(.array(.model(.dictionaryElement))))
    ),
    property(
      .arguments,
      on: [.model(.sourceExpression)],
      result: .fixed(.optional(.array(.model(.expressionArgument))))
    ),
    property(
      .interpolations,
      on: [.model(.sourceExpression)],
      result: .fixed(.array(.array(.model(.expressionArgument))))
    ),
  ]
}
