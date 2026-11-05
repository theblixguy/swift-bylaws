import BylawsSemantics

extension RuntimeTypeResolver {
  mutating func resolveLayoutGroup(
    values: [(String?, RuntimeExpression)], at location: DeclarationLocation
  ) -> RuntimeType {
    let element = layoutElementType ?? .unknown
    let result = RuntimeType.layoutGroup(element)
    guard layoutElementType != nil else {
      diagnose(
        "Group must be inside Layout or a collection replacement",
        at: location
      )
      values.forEach { _ = resolve($0.1) }
      return result
    }
    let labels = values.map(\.0)
    let isClosure = if let value = values.first, case .closure = value.1.kind {
      true
    } else { false }
    if labels == [nil], !isClosure {
      let expected: RuntimeType? = if case let .model(model) = element {
        .matcher(model)
      } else { nil }
      let condition = resolve(values[0].1, expected: expected)
      switch condition {
      case .function, .closure:
        _ = resolveCallable(
          values[0].1, input: element, expectedResult: .boolean,
          allowsThrowing: true, propagatesEffects: false, at: location
        )
      case let .keyPath(path):
        _ = resolveKeyPath(
          path,
          input: element,
          expectedResult: .boolean,
          at: location
        )
      default:
        if let expected {
          require(
            condition,
            toMatch: expected,
            subject: "the matcher",
            at: location
          )
        } else {
          diagnose(
            "Group takes a predicate, a Bool key path or matcher",
            at: location
          )
        }
      }
      return result
    }
    let input: RuntimeType
    let predicate: RuntimeExpression
    if labels.equal([nil, .where]) || labels == [nil, nil],
       case let .keyPath(path) = resolve(values[0].1)
    {
      let projection = resolveKeyPath(
        path,
        input: element,
        expectedResult: nil,
        at: location
      )
      guard case let .optional(wrapped) = projection else {
        diagnose("Group must project an optional value", at: location)
        _ = resolve(values[1].1)
        return result
      }
      input = wrapped
      predicate = values[1].1
    } else if labels == [nil] {
      input = element
      predicate = values[0].1
    } else {
      diagnose(
        "Group takes a predicate, a Bool key path, an optional key path and predicate, or a matcher",
        at: location
      )
      values.forEach { _ = resolve($0.1) }
      return result
    }
    _ = resolveCallable(
      predicate, input: input, expectedResult: .boolean,
      allowsThrowing: true, propagatesEffects: false, at: location
    )
    return result
  }
}
