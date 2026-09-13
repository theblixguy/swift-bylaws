import BylawsSemantics

extension RuntimeTypeResolver {
  mutating func resolveBuilder(
    _ values: [(String?, RuntimeExpression)],
    builder: RuntimeBuilder,
    at location: DeclarationLocation
  ) -> Bool {
    guard values.count == 1, values[0].0 == nil,
          case let .closure(body) = values[0].1.kind else { return false }
    let expected: RuntimeType = builder == .layers ? .array(.layer) :
      .array(.rule)
    let result = resolve(
      body,
      parameters: [],
      expectedResult: nil,
      requiresSynchronousBody: true,
      builder: builder
    ).result
    require(
      result,
      toMatch: body.body.containsReturn ? expected : builder.resultType,
      subject: "the builder",
      at: location
    )
    return true
  }

  mutating func resolveLayer(
    _ values: [(String?, RuntimeExpression)],
    at location: DeclarationLocation
  ) -> RuntimeType {
    let labels = values.map(\.0)
    let allowed = [
      "files",
      "modules",
      "mayImport",
      "mustImport",
      "mustNotImport",
    ]
    let order = labels
      .compactMap { label in label.flatMap { allowed.firstIndex(of: $0) } }
    guard labels.first == .some(nil),
          labels.dropFirst().allSatisfy({ $0.map(allowed.contains) == true }),
          Set(labels.compactMap(\.self)).count == labels.count - 1,
          order == order.sorted(),
          labels.contains("files")
    else {
      diagnose(
        "Layer takes one name, files, and optional import settings",
        at: location
      )
      return .layer
    }
    for (label, expression) in values {
      let expected: RuntimeType = label == nil ? .string : .array(.string)
      let type = resolve(expression, expected: expected)
      if label == "mayImport",
         type == .staticMember([.layerImportPolicy]) { continue }
      require(
        type,
        toMatch: expected,
        subject: label ?? "the layer name",
        at: expression.location
      )
    }
    return .layer
  }
}
