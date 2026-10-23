import BylawsSemantics

extension RuntimeTypeResolver {
  mutating func resolveAttributePredicate(
    _ values: [(String?, RuntimeExpression)],
    at location: DeclarationLocation
  ) -> [RuntimeType] {
    let name = resolve(values[0].1, expected: .string)
    require(
      name, toMatch: .string, subject: "the attribute name",
      at: values[0].1.location
    )
    let result = resolveCallable(
      values[1].1, input: .model(.sourceExpression),
      expectedResult: .boolean, allowsThrowing: true, at: location
    )
    return [name, result]
  }
}
