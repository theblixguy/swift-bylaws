extension SupportedAPI {
  package static let runtimeMembers =
    collectionRuntimeMembers
      + pathRuntimeMembers
      + dictionaryRuntimeMembers
      + stringRuntimeMembers
      + selectionRuntimeMembers
      + codebaseRuntimeMembers
      + projectIndexRuntimeMembers
      + checkRuntimeMembers
      + resultRuntimeMembers
      + memberMatcherRuntimeMembers
      + rangeRuntimeMembers
      + modelRuntimeMembers
      + expressionRuntimeMembers
      + bodyRuntimeMembers
      + compilationBranchRuntimeMembers
      + modelMethodRuntimeMembers
      + indexModelRuntimeMembers
      + syntaxRuntimeMembers
      + typeRuntimeMembers
      + manifestRuntimeMembers
      + bazelRuntimeMembers

  static let collectionReceivers: Set<RuntimeReceiver> = [
    .array, .set, .selection,
  ]

  static let declarationReceivers: Set<RuntimeReceiver> = [
    .model(.actor), .model(.classDeclaration), .model(.enumDeclaration),
    .model(.function), .model(.initializer), .model(.nominalType),
    .model(.property), .model(.protocolDeclaration),
    .model(.structDeclaration), .model(.typealiasDeclaration),
  ]

  static let attributedReceivers = declarationReceivers.union([
    RuntimeReceiver.model(.extensionDeclaration),
    .model(.importDeclaration),
  ])

  static let typeReceivers: Set<RuntimeReceiver> = [
    .model(.actor), .model(.classDeclaration), .model(.enumDeclaration),
    .model(.nominalType), .model(.structDeclaration),
  ]

  static let inheritedTypeReceivers = typeReceivers.union([
    RuntimeReceiver.model(.extensionDeclaration),
    .model(.protocolDeclaration),
  ])

  package static func runtimeProperty(
    named name: Member,
    on receiver: RuntimeReceiver
  ) -> RuntimeMemberAPI? {
    runtimeMembers(named: name, on: receiver).first {
      if case .property = $0.kind { true } else { false }
    }
  }

  package static func runtimeMethod(
    named name: Member,
    on receiver: RuntimeReceiver
  ) -> RuntimeMemberAPI? {
    runtimeMembers(named: name, on: receiver).first {
      if case .method = $0.kind { true } else { false }
    }
  }

  package static func runtimeMembers(
    named name: Member,
    on receiver: RuntimeReceiver
  ) -> [RuntimeMemberAPI] {
    runtimeMemberLookup[receiver]?[name] ?? []
  }

  private static let runtimeMemberLookup: [
    RuntimeReceiver: [Member: [RuntimeMemberAPI]]
  ] = runtimeMembers.reduce(into: [:]) { lookup, api in
    for receiver in api.receivers {
      lookup[receiver, default: [:]][api.name, default: []].append(api)
    }
  }
}

extension SupportedAPI {
  package static func property(
    _ name: Member,
    on receivers: Set<RuntimeReceiver>,
    result: RuntimeResult,
    canSuspend: Bool = false
  ) -> RuntimeMemberAPI {
    RuntimeMemberAPI(
      receivers: receivers,
      name: name,
      kind: .property(result),
      canSuspend: canSuspend
    )
  }

  package static func method(
    _ name: Member,
    on receivers: Set<RuntimeReceiver>,
    arguments: RuntimeCallArguments,
    result: RuntimeResult,
    canSuspend: Bool = false
  ) -> RuntimeMemberAPI {
    guard let method = name.method else {
      preconditionFailure(
        "SupportedAPI.Member.\(name.rawValue) is not a runtime method"
      )
    }
    return RuntimeMemberAPI(
      receivers: receivers,
      name: name,
      kind: .method(
        RuntimeCall(
          method: method,
          arguments: arguments,
          result: result
        )
      ),
      canSuspend: canSuspend
    )
  }
}
