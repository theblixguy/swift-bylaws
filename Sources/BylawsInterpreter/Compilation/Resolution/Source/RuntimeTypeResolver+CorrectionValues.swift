import BylawsSemantics

extension RuntimeTypeResolver {
  mutating func resolveCorrectionConstructor(
    typeArguments: [RuntimeType], values: [(String?, RuntimeExpression)],
    at location: DeclarationLocation
  ) -> RuntimeType {
    if !typeArguments.isEmpty {
      diagnose("SourceCorrection takes no generic arguments", at: location)
    }
    let labels = values.map(\.0)
    let expected: RuntimeType? = if labels == [nil] {
      .sourceFix
    } else if labels.equal([.edits]) {
      .array(.sourceEdit)
    } else if labels.equal([.combining]) {
      .array(.sourceCorrection)
    } else {
      nil
    }
    guard let expected, let value = values.first?.1 else {
      diagnose(
        "SourceCorrection takes edits, a fix or combined corrections",
        at: location,
        resolvingArguments: values
      )
      return .sourceCorrection
    }
    require(
      resolve(value, expected: expected),
      toMatch: expected,
      subject: "the correction",
      at: value.location
    )
    return .sourceCorrection
  }
}
