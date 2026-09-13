extension SupportedAPI {
  static let indexModelRuntimeMembers: [RuntimeMemberAPI] = [
    property(
      .targets,
      on: [.model(.importGraph)],
      result: .fixed(.array(.model(.importGraphTarget)))
    ),
    property(
      .name,
      on: [.model(.importGraphTarget)],
      result: .fixed(.string)
    ),
    property(
      .imports,
      on: [.model(.importGraphTarget)],
      result: .fixed(.array(.string))
    ),
    property(
      .importedBy,
      on: [.model(.importGraphTarget)],
      result: .fixed(.array(.string))
    ),
    property(
      .instability,
      on: [.model(.importGraphTarget)],
      result: .fixed(.double)
    ),

    property(
      .symbol,
      on: [.model(.indexReference)],
      result: .fixed(.model(.indexSymbol))
    ),
    property(.module, on: [.model(.indexReference)], result: .fixed(.string)),
    property(.file, on: [.model(.indexReference)], result: .fixed(.string)),
    property(.line, on: [.model(.indexReference)], result: .fixed(.integer)),
    property(
      .column,
      on: [.model(.indexReference)],
      result: .fixed(.integer)
    ),
    property(
      .roles,
      on: [.model(.indexReference)],
      result: .fixed(.symbolRoles)
    ),
    property(.usr, on: [.model(.indexSymbol)], result: .fixed(.string)),
    property(.name, on: [.model(.indexSymbol)], result: .fixed(.string)),
    property(
      .kind,
      on: [.model(.indexSymbol)],
      result: .fixed(.staticMember([.indexSymbolKind]))
    ),
  ]
}
