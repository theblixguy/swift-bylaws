extension SupportedAPI {
  static let dictionaryRuntimeMembers: [RuntimeMemberAPI] = [
    property(.count, on: [.dictionary], result: .fixed(.integer)),
    property(.isEmpty, on: [.dictionary], result: .fixed(.boolean)),
    method(
      .mapValues,
      on: [.dictionary],
      arguments: .exact([.init(nil, .dictionaryValueCallable)]),
      result: .mappedDictionary
    ),
  ]
}
