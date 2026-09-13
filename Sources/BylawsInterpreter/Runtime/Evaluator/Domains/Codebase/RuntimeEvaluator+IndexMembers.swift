extension RuntimeEvaluator {
  func indexReferenceMember(
    _ name: SupportedAPI.Member,
    _ value: RuntimeIndexReference
  ) -> RuntimeValue? {
    switch name {
    case .symbol: .model(.indexSymbol(value.symbol))
    case .module: .string(value.module)
    case .file: .string(value.file)
    case .line: .integer(value.line)
    case .column: .integer(value.column)
    case .roles: .symbolRoles(value.roles)
    default: nil
    }
  }

  func indexSymbolMember(
    _ name: SupportedAPI.Member,
    _ value: RuntimeIndexSymbol
  ) -> RuntimeValue? {
    switch name {
    case .usr: .string(value.usr)
    case .name: .string(value.name)
    case .kind: .member(naming: value.kind)
    default: nil
    }
  }
}
