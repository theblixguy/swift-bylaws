extension SupportedAPI {
  static let memberMatcherRuntimeMembers: [RuntimeMemberAPI] = [
    Member.all,
    .any,
    .none,
  ].map {
    method(
      $0,
      on: [.staticType("Matcher")],
      arguments: .exact([.init(nil, .any), .init(.matching, .any)]),
      result: .fixed(.matcher(nil))
    )
  }
}
