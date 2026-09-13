import SwiftSyntax

enum ManifestListDecoder {
  static func list<Element: Sendable & Hashable & Codable>(
    from expression: ExprSyntax?,
    field: String,
    resolver: ManifestSyntaxResolver,
    nilMeansEmpty: Bool = false,
    decode: (ExprSyntax) -> Element?
  ) -> ManifestList<Element> {
    guard let expression else { return .init() }
    if nilMeansEmpty,
       expression.is(NilLiteralExprSyntax.self) { return .init() }
    let expressions = resolver.array(from: expression)
    var values: [Element] = []
    var unresolved = expressions.unresolved.map {
      resolver.issue(field: field, expression: $0)
    }
    for expression in expressions.known {
      if let value = decode(expression) {
        values.append(value)
      } else {
        unresolved.append(resolver.issue(field: field, expression: expression))
      }
    }
    return ManifestList(knownValues: values, unresolvedValues: unresolved)
  }

  static func memberNames(
    from expression: ExprSyntax?,
    field: String,
    resolver: ManifestSyntaxResolver
  ) -> ManifestList<String> {
    list(
      from: expression,
      field: field,
      resolver: resolver,
      nilMeansEmpty: true
    ) {
      memberName(from: $0, resolver: resolver)
    }
  }

  static func memberName(
    from expression: ExprSyntax,
    resolver: ManifestSyntaxResolver
  ) -> String? {
    resolver.memberName(from: expression)
      ?? resolver.string(from: expression)
      ?? resolver.resolvedExpression(from: expression)?
      .as(IntegerLiteralExprSyntax.self)?.literal.text
  }

  static func scalarMutation<Value>(
    _ mutation: ManifestMutation,
    current: Value?,
    resolver: ManifestSyntaxResolver,
    decode: (ExprSyntax) -> Value?
  ) -> (value: Value?, issues: [PackageManifest.UnresolvedValue]) {
    guard mutation.conditionHolds != false else { return (current, []) }
    guard mutation.conditionHolds == true,
          mutation.replacesValues,
          let expression = mutation.value
    else {
      return (
        current,
        [resolver.issue(
          field: mutation.field.rawValue,
          expression: mutation.syntax
        )]
      )
    }
    if expression.is(NilLiteralExprSyntax.self) { return (nil, []) }
    guard let value = decode(expression) else {
      return (
        current,
        [resolver.issue(
          field: mutation.field.rawValue,
          expression: expression
        )]
      )
    }
    return (value, [])
  }

  static func applying<Element: Sendable & Hashable & Codable>(
    _ mutation: ManifestMutation,
    to values: ManifestList<Element>,
    resolver: ManifestSyntaxResolver,
    nilMeansEmpty: Bool = false,
    decode: (ExprSyntax) -> Element?
  ) -> ManifestList<Element> {
    guard mutation.conditionHolds != false else { return values }
    let existing: ManifestList<Element> = if mutation.replacesValues,
                                             mutation.conditionHolds == true
    {
      .init()
    } else if mutation.invalidatesExistingValues
      || (mutation.replacesValues && mutation.conditionHolds == nil)
    {
      ManifestList(
        conditionalValues: values.possibleValues,
        unresolvedValues: values.unresolvedValues
      )
    } else {
      values
    }
    let conditionIssues = mutation.conditionHolds == nil
      ? [resolver.issue(
        field: mutation.field.rawValue,
        expression: mutation.syntax
      )]
      : []
    guard let expression = mutation.value else {
      return existing.adding(
        conditionIssues + [
          resolver.issue(
            field: mutation.field.rawValue,
            expression: mutation.syntax
          ),
        ]
      )
    }
    let appended: ManifestList<Element> = if mutation.isList {
      list(
        from: expression,
        field: mutation.field.rawValue,
        resolver: resolver,
        nilMeansEmpty: nilMeansEmpty,
        decode: decode
      )
    } else if let value = decode(expression) {
      ManifestList(knownValues: [value])
    } else {
      ManifestList(
        unresolvedValues: [
          resolver.issue(
            field: mutation.field.rawValue,
            expression: expression
          ),
        ]
      )
    }
    return ManifestList(
      knownValues: existing.knownValues
        + (mutation.conditionHolds == true ? appended.knownValues : []),
      conditionalValues: existing.conditionalValues
        + appended.conditionalValues
        + (mutation.conditionHolds == nil ? appended.knownValues : []),
      unresolvedValues: existing.unresolvedValues
        + appended.unresolvedValues
        + conditionIssues
    )
  }
}

extension ManifestList {
  func adding(_ issues: [PackageManifest.UnresolvedValue]) -> Self {
    Self(
      knownValues: knownValues,
      conditionalValues: conditionalValues,
      unresolvedValues: unresolvedValues + issues
    )
  }
}
