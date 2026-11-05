extension SupportedAPI {
  static let layoutContentRuntimeMembers: [RuntimeMemberAPI] = (
    [.layout, .group, .separator, .sequence, .newline, .blankLine] as [Member]
  ).map { name in
    method(
      name,
      on: [.staticType("LayoutContent")],
      arguments: .exact([.init(nil)]),
      result: .fixed(.layoutContent(.unknown))
    )
  }
}
