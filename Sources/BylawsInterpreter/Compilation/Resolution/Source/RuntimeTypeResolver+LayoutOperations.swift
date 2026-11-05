import BylawsSemantics

extension RuntimeTypeResolver {
  mutating func resolveLayoutOperation(
    values: [(String?, RuntimeExpression)], at location: DeclarationLocation
  ) -> RuntimeType {
    let labels = values.map(\.0)
    let builder = labels == [nil, nil]
      || labels.equal([nil, .when, nil])
    let stored = labels.equal([nil, .layout])
      || labels.equal([nil, .layout, .when])
    guard builder || stored else {
      diagnose(
        "Layout takes source elements and a layout closure or layout: value",
        at: location
      )
      values.forEach { _ = resolve($0.1) }
      return .layoutCorrection
    }
    requireEffects(canSuspend: false, canThrow: true, at: location)
    let elements = resolve(values[0].1)
    let element = elements.collectionElement
    if !element.providesSource {
      diagnose("Layout must use a collection of captured source", at: location)
    }
    if values.count == 3 {
      let index = builder ? 1 : 2
      let expected = RuntimeType.optional(.sourceLayoutCondition)
      require(
        resolve(values[index].1, expected: expected),
        toMatch: expected,
        subject: "the condition",
        at: location
      )
    }
    let outerElement = layoutElementType
    layoutElementType = element
    defer {
      layoutElementType = outerElement
    }
    let body = values[builder ? values.count - 1 : 1].1
    if builder {
      resolveLayoutClosure(body)

    } else {
      let layout = resolve(body, expected: .layoutContent(element))
      if !layout.providesLayout {
        require(
          layout,
          toMatch: .layoutContent(element),
          subject: "the layout",
          at: location
        )
      }
    }
    return .layoutCorrection
  }
}
