extension SupportedAPI {
  static let pathRuntimeMembers: [RuntimeMemberAPI] = [
    property(.path, on: [.url], result: .fixed(.string)),
    property(.lastPathComponent, on: [.url], result: .fixed(.string)),
    property(.pathExtension, on: [.url], result: .fixed(.string)),
    method(
      .deletingLastPathComponent,
      on: [.url],
      arguments: .exact([]),
      result: .receiver
    ),
  ]
}
