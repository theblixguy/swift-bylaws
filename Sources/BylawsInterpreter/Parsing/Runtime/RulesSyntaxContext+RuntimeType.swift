import BylawsSyntax

extension RulesSyntaxContext {
  func runtimeType(
    from type: TypeSyntax,
    diagnostics: inout [Diagnostic]
  ) -> SupportedAPI.RuntimeType? {
    let writtenType = type.trimmedDescription
    let resolvedType = SupportedAPI.RuntimeType(writtenType: writtenType)
    guard !resolvedType.containsUnknown else {
      diagnostics.append(
        error(
          "portable rules do not support the '\(writtenType)' type",
          at: type
        )
      )
      return nil
    }
    return resolvedType
  }
}
