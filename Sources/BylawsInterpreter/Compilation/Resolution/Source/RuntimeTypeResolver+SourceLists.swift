import BylawsSemantics

extension RuntimeTypeResolver {
  mutating func resolveListCorrection(
    _ constructor: SupportedAPI.Constructor,
    typeArguments: [RuntimeType],
    values: [(String?, RuntimeExpression)],
    at location: DeclarationLocation
  ) -> RuntimeType {
    requireEffects(canSuspend: false, canThrow: true, at: location)
    if !typeArguments.isEmpty {
      diagnose(
        "\(constructor.rawValue) takes no generic arguments",
        at: location
      )
    }
    let labels = values.map(\.0)
    if constructor == .remove {
      guard labels == [nil] else {
        diagnose("Remove takes one captured source value", at: location)
        values.forEach { _ = resolve($0.1) }
        return .sourceCorrection
      }
      if !resolve(values[0].1).providesSource {
        diagnose(
          "Remove takes a captured source value",
          at: values[0].1.location
        )
      }
      return .sourceCorrection
    }
    guard labels.equal([nil, .into]) || labels.equal([nil, .into, .at]) else {
      diagnose(
        "Insert takes text, a SourceList and an optional position",
        at: location
      )
      values.forEach { _ = resolve($0.1) }
      return .sourceCorrection
    }
    require(
      resolve(values[0].1),
      toMatch: .string,
      subject: "the inserted text",
      at: values[0].1.location
    )
    if case .sourceList = resolve(values[1].1) {} else {
      diagnose("Insert takes a SourceList", at: values[1].1.location)
    }
    if values.count == 3 {
      let position = RuntimeType.staticMember([.sourceListPosition])
      require(
        resolve(values[2].1, expected: position),
        toMatch: position,
        subject: "the position",
        at: values[2].1.location
      )
    }
    return .sourceCorrection
  }

  mutating func resolveSourceListIndex(
    values: [(String?, RuntimeExpression)],
    at location: DeclarationLocation
  ) -> RuntimeType {
    guard values.map(\.0) == [nil] else {
      diagnose("SourceListPosition.index takes one Int", at: location)
      values.forEach { _ = resolve($0.1) }
      return .staticMember([.sourceListPosition])
    }
    require(
      resolve(values[0].1),
      toMatch: .integer,
      subject: "the index",
      at: values[0].1.location
    )
    return .staticMember([.sourceListPosition])
  }
}
