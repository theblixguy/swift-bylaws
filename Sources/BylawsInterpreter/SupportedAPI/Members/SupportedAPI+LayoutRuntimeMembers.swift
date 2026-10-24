extension SupportedAPI {
  static let layoutRuntimeMembers: [RuntimeMemberAPI] = [
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
      on: [.array, .arraySlice, .selection],
      arguments: .alternatives([
        [.init(nil)],
        [.init(.whenLineExceeds, .exact(.optional(.integer))), .init(nil)],
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
    .sourceToken, .sourceTrivia, .sourceFile, .sourceNode, .sourceExpression,
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
    case .sourceSlice: true
    case let .model(model): SupportedAPI.sourceProvidingModels.contains(model)
    default: false
    }
  }

  var supportsLayout: Bool {
    if providesSource { return true }
    if let element = sequenceElement { return element.providesSource }
    return switch self {
    case .sourceLayout, .sourceEdit, .layoutOperation, .layoutGroup,
         .conditionalLayoutOperation: true
    default: false
    }
  }
}
