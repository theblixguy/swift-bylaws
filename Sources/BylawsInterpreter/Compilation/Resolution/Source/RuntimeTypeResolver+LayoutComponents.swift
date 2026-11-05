import BylawsSemantics

extension RuntimeTypeResolver {
  mutating func resolveLayoutComponent(
    _ constructor: SupportedAPI.Constructor,
    values: [(String?, RuntimeExpression)], at location: DeclarationLocation
  ) -> RuntimeType {
    let labels = values.map(\.0)
    let option: SupportedAPI.ArgumentLabel? = switch constructor {
    case .wrap: .width
    case .lines: .boundaries
    default: nil
    }
    let valid = if let option {
      labels == [nil] || labels.equal([.layout])
        || labels.equal([nil, option]) || labels.equal([.layout, option])
        || labels.equal([option, nil])
    } else { labels == [nil] || labels.equal([.layout]) }
    let result: RuntimeType = constructor == .sourceLayout ? .sourceLayout :
      .layoutOperation(constructor)
    guard valid else {
      diagnose(
        "\(constructor.rawValue) takes source elements, a layout closure or layout: value",
        at: location
      )
      values.forEach { _ = resolve($0.1) }
      return result
    }
    if let option,
       let value = values.first(where: { $0.0 == option.rawValue })?.1
    {
      let expected: RuntimeType = option == .width ? .optional(.integer) :
        .staticMember([.linesBoundaries])
      require(
        resolve(value, expected: expected),
        toMatch: expected,
        subject: option == .width ? "the width" : "the boundaries",
        at: location
      )
    }
    let stored = labels.first == "layout"
    let firstLabel = values[0].0
    let bodyIndex = firstLabel == "width" || firstLabel == "boundaries" ? 1 : 0
    let body = values[bodyIndex].1
    if !stored, case .closure = body.kind {
      resolveLayoutClosure(body, builder: .sourceLayout)
      return result
    }
    let expected: RuntimeType? = if constructor == .sourceLayout,
                                    case .array = body.kind
    {
      .array(.sourceLayout)
    } else if stored || constructor == .sourceLayout { .sourceLayout }
    else { nil }
    let type = resolve(body, expected: expected)
    switch type {
    case .function where !stored,
         .closure where !stored: resolveLayoutClosure(
        body,
        builder: .sourceLayout
      )
    default:
      let supported = if stored {
        type.providesLayout
      } else if constructor == .sourceLayout {
        type.providesLayout || type.providesSource
          || type.sequenceElement?.providesSource == true
          || type == .array(.sourceLayout) || RuntimeBuilder.correction
          .accepts(type)
      } else {
        bodyIndex == 0 && type.sequenceElement?.providesSource == true
      }
      if !supported {
        diagnose(
          "\(constructor.rawValue) takes source elements, a layout closure or layout: value",
          at: location
        )
      }
    }
    return result
  }
}
