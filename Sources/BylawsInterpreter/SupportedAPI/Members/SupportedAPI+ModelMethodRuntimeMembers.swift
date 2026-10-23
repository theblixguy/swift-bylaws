extension SupportedAPI {
  static let modelMethodRuntimeMembers: [RuntimeMemberAPI] = [
    modelMethod(
      .imports,
      on: [.sourceFile],
      arguments: [.init(nil, .exact(.string))],
      result: .fixed(.boolean)
    ),
    modelMethod(
      .calls,
      on: [.sourceFile, .function, .property],
      arguments: [.init(nil, .exact(.string))],
      result: .fixed(.boolean)
    ),
    modelMethod(
      .references,
      on: [.functionCall, .typeReference],
      arguments: [.init(nil, .exact(.string))],
      result: .fixed(.boolean)
    ),
    modelMethod(
      .hasArgumentLabel,
      on: [.functionCall],
      arguments: [.init(nil, .exact(.string))],
      result: .fixed(.boolean)
    ),
    method(
      .hasAttribute,
      on: attributedReceivers.union([.model(.sourceNode)]),
      arguments: .alternatives([
        [.init(nil, .exact(.string))],
        [.init(nil, .exact(.string)),
         .init(
           .argument,
           .callable(input: .model(.sourceExpression), result: .boolean)
         )],
      ]),
      result: .fixed(.boolean)
    ),
    method(
      .attribute,
      on: attributedReceivers.union([.model(.sourceNode)]),
      arguments: .exact([.init(.named, .exact(.string))]),
      result: .fixed(.optional(.model(.attribute)))
    ),
    inheritanceMethod(.inherits, on: inheritedTypeReceivers, label: .from),
    inheritanceMethod(
      .directlyInherits,
      on: inheritedTypeReceivers,
      label: .from
    ),
    inheritanceMethod(.conforms, on: inheritedTypeReceivers, label: .to),
    inheritanceMethod(
      .directlyConforms,
      on: inheritedTypeReceivers,
      label: .to
    ),
    method(
      .withSyntax,
      on: [.model(.sourceFile)],
      arguments: .alternatives([
        [.init(
          nil,
          .callable(input: .model(.syntaxSourceFile), result: nil)
        )],
        [
          .init(.of, .exact(.model(.classDeclaration))),
          .init(.as, .exact(.staticType(ModelType.syntaxClass.rawValue))),
          .init(nil, .callable(input: .model(.syntaxClass), result: nil)),
        ],
      ]),
      result: .syntaxClosureResult
    ),
    method(
      .tokens,
      on: [.model(.syntaxSourceFile)],
      arguments: .exact([.init(
        .viewMode,
        .exact(.staticMember([.tokenViewMode]))
      )]),
      result: .fixed(.array(.model(.syntaxToken)))
    ),
  ]

  private static func modelMethod(
    _ name: Member,
    on receivers: [ModelType],
    arguments: [RuntimeCallParameter],
    result: RuntimeResult
  ) -> RuntimeMemberAPI {
    method(
      name,
      on: Set(receivers.map(RuntimeReceiver.model)),
      arguments: .exact(arguments),
      result: result
    )
  }

  private static func inheritanceMethod(
    _ name: Member,
    on receivers: Set<RuntimeReceiver>,
    label: ArgumentLabel
  ) -> RuntimeMemberAPI {
    method(
      name,
      on: receivers,
      arguments: .exact([.init(label, .exact(.string))]),
      result: .fixed(.boolean)
    )
  }
}
