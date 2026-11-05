extension SupportedAPI {
  static let layoutRuntimeMembers: [RuntimeMemberAPI] = [
    property(
      .boundariesType,
      on: [.staticType("Lines")],
      result: .fixed(.staticType("Lines.Boundaries"))
    ),
    method(
      .applying,
      on: [.layoutCorrection],
      arguments: .alternatives([
        [.init(nil)],
        [.init(.toEach), .init(nil)],
      ]),
      result: .receiver,
      canThrow: true
    ),
    method(
      .maximumLineLength, on: [.staticType("SourceLayoutCondition")],
      arguments: .exact([.init(nil, .oneOf([
        .integerRange, .integerClosedRange, .integerRangeFrom,
        .integerRangeThrough, .integerRangeUpTo,
      ]))]), result: .fixed(.sourceLayoutCondition)
    ),
    property(
      .newline,
      on: [.staticType("SourceLayout")],
      result: .fixed(.sourceLayout)
    ),
    property(
      .blankLine,
      on: [.staticType("SourceLayout")],
      result: .fixed(.sourceLayout)
    ),
    property(
      .softBreak,
      on: [.staticType("SourceLayout")],
      result: .fixed(.sourceLayout)
    ),
    property(.layout, on: [.sourceLayout], result: .fixed(.sourceLayout)),
    method(
      .sorted,
      on: [.layoutGroup],
      arguments: .alternatives([
        [.init(.by, .collectionComparator)],
        [.init(nil, .collectionComparator)],
      ]),
      result: .receiver
    ),
    property(
      .spacing,
      on: Set(sourceProvidingModels.map(RuntimeReceiver.model))
        .union([.sourceSlice]),
      result: .fixed(.sourceSpacing), canThrow: true
    ),
    property(.before, on: [.sourceSpacing], result: .fixed(.sourceSlice)),
    property(.after, on: [.sourceSpacing], result: .fixed(.sourceSlice)),
    method(
      .replacement,
      on: [.array, .arraySlice, .selection, .sourceList],
      arguments: .alternatives([
        [.init(nil)],
        [.init(.when, .exact(.optional(.sourceLayoutCondition))), .init(nil)],
        [.init(.layout)],
        [
          .init(.layout),
          .init(.when, .exact(.optional(.sourceLayoutCondition))),
        ],
      ]),
      result: .fixed(.sourceEdit), canThrow: true
    ),
    property(
      .argument,
      on: [.model(.attribute)],
      result: .fixed(.optional(.model(.sourceExpression)))
    ),
    property(
      .isKeyPath,
      on: [.model(.sourceExpression)],
      result: .fixed(.boolean)
    ),
    property(
      .members,
      on: [.model(.sourceNode)],
      result: .fixed(.array(.model(.sourceNode)))
    ),
    property(
      .modifiers,
      on: [.model(.sourceNode)],
      result: .fixed(.array(.model(.sourceNode)))
    ),
    property(
      .parameters,
      on: [.model(.sourceNode)],
      result: .fixed(.array(.model(.sourceNode)))
    ),
    property(
      .cases,
      on: [.model(.sourceNode)],
      result: .fixed(.array(.model(.sourceNode)))
    ),
    property(
      .statements,
      on: [.model(.sourceNode)],
      result: .fixed(.array(.model(.sourceNode)))
    ),
    property(
      .property,
      on: [.model(.sourceNode)],
      result: .fixed(.optional(.model(.property)))
    ),
    property(
      .name,
      on: [.model(.sourceNode)],
      result: .fixed(.optional(.string))
    ),
    property(
      .attributes,
      on: [.model(.sourceNode)],
      result: .fixed(.array(.model(.attribute)))
    ),
  ]

  static let sourceProvidingModels: Set<ModelType> = [
    .sourceToken, .sourceTrivia, .sourceFile, .sourceNode, .sourceIfExpression,
    .sourceExpression,
    .sourceAssignment,
    .variableBinding, .classDeclaration, .actor, .structDeclaration,
    .enumDeclaration, .nominalType, .protocolDeclaration,
    .extensionDeclaration, .function, .property, .initializer,
    .importDeclaration, .typealiasDeclaration, .functionCall,
    .callArgument, .expressionArgument, .dictionaryElement, .attribute,
    .enumCase,
  ]
}

extension SupportedAPI.RuntimeType {
  var providesSource: Bool {
    switch self {
    case .sourceSlice, .sourceList: true
    case let .model(model): SupportedAPI.sourceProvidingModels.contains(model)
    default: false
    }
  }

  var providesLayout: Bool {
    switch self {
    case .sourceLayout, .layoutOperation(.line), .layoutOperation(.joined),
         .layoutOperation(.lines),
         .layoutOperation(.indent), .layoutOperation(.wrap),
         .layoutOperation(.align): true
    default: false
    }
  }

  var supportsSourceLayout: Bool {
    switch self {
    case .layoutContent, .layoutGroup, .conditionalLayoutOperation: false
    default: supportsLayout
    }
  }

  var supportsLayout: Bool {
    if providesSource { return true }
    if let element = sequenceElement {
      return element.providesSource || RuntimeBuilder.correction.accepts(self)
    }
    return switch self {
    case .sourceLayout, .layoutContent, .sourceEdit, .sourceFix,
         .sourceCorrection, .layoutCorrection,
         .layoutOperation, .layoutGroup,
         .conditionalLayoutOperation:
      true
    default: false
    }
  }
}
