extension SupportedAPI {
  static let correctionRuntimeMembers: [RuntimeMemberAPI] = [
    property(.offender, on: [.fixContext], result: .fixOffender),
    property(
      .source,
      on: [.fixContext],
      result: .fixed(.sourceSlice),
      canThrow: true
    ),
    property(
      .file,
      on: [.fixContext],
      result: .fixed(.sourceSlice),
      canThrow: true
    ),
    property(
      .codebase,
      on: [.fixContext],
      result: .fixed(.codebase),
      canThrow: true
    ),
    property(.text, on: [.sourceSlice], result: .fixed(.string)),
    property(.file, on: [.sourceSlice], result: .fixed(.sourceSlice)),
    property(.filePath, on: [.sourceSlice], result: .fixed(.string)),
    property(.range, on: [.sourceSlice], result: .fixed(.integerRange)),
    method(
      .replacement,
      on: [.sourceSlice],
      arguments: .exact([.init(.with, .exact(.string))]),
      result: .fixed(.sourceEdit)
    ),
    method(
      .matches,
      on: [.sourceSlice],
      arguments: .exact([.init(.of, .exact(.regex))]),
      result: .fixed(.array(.sourceSlice))
    ),
    method(
      .slice,
      on: [.sourceSlice],
      arguments: .exact([.init(nil, .exact(.integerRange))]),
      result: .fixed(.sourceSlice), canThrow: true
    ),
    method(
      .only,
      on: [.array],
      arguments: .exact([]),
      result: .fixed(.sourceSlice), canThrow: true
    ),
    method(
      .withFix,
      on: [.violations],
      arguments: .alternatives([
        [.init(nil)],
        [.init(nil, .oneOf([.string, .optional(.string)])), .init(nil)],
      ]),
      result: .receiver,
      canSuspend: true, canThrow: true
    ),
    method(
      .argument,
      on: [.model(.functionCall)],
      arguments: .exact([.init(.labeled, .exact(.string))]),
      result: .fixed(.model(.callArgument)), canThrow: true
    ),
  ] + sourceProjectionMembers

  private static let sourceProjectionMembers: [RuntimeMemberAPI] = [
    property(
      .source,
      on: sourceReceivers,
      result: .fixed(.sourceSlice),
      canThrow: true
    ),
    property(
      .nameSource,
      on: declarationReceivers.union([
        .model(.variableBinding), .model(.enumCase), .model(.importDeclaration),
        .model(.extensionDeclaration), .model(.functionCall),
      ]),
      result: .fixed(.sourceSlice), canThrow: true
    ),
    property(
      .bodySource,
      on: declarationReceivers.subtracting([.model(.typealiasDeclaration)])
        .union([.model(.extensionDeclaration)]),
      result: .fixed(.sourceSlice), canThrow: true
    ),
    property(
      .calledExpressionSource,
      on: [.model(.functionCall)],
      result: .fixed(.sourceSlice), canThrow: true
    ),
    property(
      .memberNameSource,
      on: [.model(.functionCall)],
      result: .fixed(.sourceSlice), canThrow: true
    ),
    property(
      .expressionSource,
      on: [.model(.callArgument), .model(.expressionArgument)],
      result: .fixed(.sourceSlice), canThrow: true
    ),
    property(
      .labelSource,
      on: [.model(.callArgument), .model(.expressionArgument)],
      result: .fixed(.optional(.sourceSlice)), canThrow: true
    ),
  ]

  private static let sourceReceivers = declarationReceivers.union([
    RuntimeReceiver.model(.sourceFile), .model(.sourceNode),
    .model(.sourceExpression), .model(.functionCall),
    .model(.callArgument), .model(.expressionArgument),
    .model(.sourceAssignment), .model(.variableBinding), .model(.enumCase),
    .model(.importDeclaration),
    .model(.extensionDeclaration),
  ])
}
