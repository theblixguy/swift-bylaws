import BylawsSemantics

extension RuntimeTypeResolver {
  mutating func resolveMemberMatcher(
    types: [RuntimeType], values: [(String?, RuntimeExpression)],
    at location: DeclarationLocation
  ) -> RuntimeType {
    guard types.count == 1, case let .model(subject) = types[0] else {
      diagnose("Matcher takes one supported subject type", at: location)
      return .matcher(nil)
    }
    guard case let .keyPath(path) = resolve(values[0].1) else {
      diagnose(
        "Matcher takes a key path to a sequence of members",
        at: values[0].1.location
      )
      return .matcher(subject)
    }
    let members = resolveKeyPath(
      path,
      input: .model(subject),
      expectedResult: nil,
      at: values[0].1.location
    )
    guard case let .model(member)? = members.sequenceElement,
          SupportedAPI
          .runtimeProperty(named: .location, on: .model(member)) != nil
    else {
      diagnose(
        "the key path must select a sequence of members",
        at: values[0].1.location
      )
      return .matcher(subject)
    }
    let child = resolve(values[1].1)
    requireMatcher(child, subject: member, at: values[1].1.location)
    return .matcher(subject)
  }
}
