extension SupportedAPI {
  static let collectionRuntimeMembers: [RuntimeMemberAPI] = [
    property(.count, on: collectionReceivers, result: .fixed(.integer)),
    property(.isEmpty, on: collectionReceivers, result: .fixed(.boolean)),
    property(
      .first,
      on: [.array, .selection],
      result: .optionalCollectionElement
    ),
    method(
      .filter,
      on: collectionReceivers,
      arguments: .exact([.init(nil, .collectionCallable(result: .boolean))]),
      result: .collection
    ),
    method(
      .map,
      on: collectionReceivers,
      arguments: .exact([.init(nil, .collectionCallable(result: nil))]),
      result: .closureResult
    ),
    method(
      .compactMap,
      on: collectionReceivers,
      arguments: .exact([.init(nil, .collectionCallable(result: nil))]),
      result: .optionalClosureResult
    ),
    method(
      .flatMap,
      on: collectionReceivers,
      arguments: .exact([.init(nil, .collectionCallable(result: nil))]),
      result: .flattenedClosureResult
    ),
    method(
      .contains,
      on: collectionReceivers,
      arguments: .alternatives([
        [.init(nil, .collectionCallable(result: .boolean))],
        [.init(nil, .collectionElement)],
        [.init(.where, .collectionCallable(result: .boolean))],
      ]),
      result: .fixed(.boolean)
    ),
    method(
      .allSatisfy,
      on: collectionReceivers,
      arguments: .exact([.init(nil, .collectionCallable(result: .boolean))]),
      result: .fixed(.boolean)
    ),
    method(
      .isSubset,
      on: [.set],
      arguments: .exact([.init(.of, .sequenceOfCollectionElement)]),
      result: .fixed(.boolean)
    ),
  ]

  static let stringRuntimeMembers: [RuntimeMemberAPI] = [
    property(.count, on: [.string], result: .fixed(.integer)),
    property(.isEmpty, on: [.string], result: .fixed(.boolean)),
    property(.description, on: [.string], result: .fixed(.string)),
    property(.first, on: [.string], result: .fixed(.optional(.string))),
    stringMethod(.hasPrefix),
    stringMethod(.hasSuffix),
    stringMethod(.contains),
    method(
      .lowercased,
      on: [.string],
      arguments: .exact([]),
      result: .fixed(.string)
    ),
  ]

  static let selectionRuntimeMembers: [RuntimeMemberAPI] = [
    property(.queryDescription, on: [.selection], result: .fixed(.string)),
    method(
      .where,
      on: [.selection],
      arguments: .exact([.init(nil, .selectionFilter)]),
      result: .receiver
    ),
    selectionStringMethod(.named),
    selectionStringMethod(.suffixed),
    selectionStringMethod(.prefixed),
    selectionStringMethod(.excluding),
    selectionStringMethod(.under),
    selectionStringMethod(.outside),
    method(
      .nameMatching,
      on: [.selection],
      arguments: .exact([.init(nil, .exact(.string))]),
      result: .receiver
    ),
    method(
      .violations,
      on: [.selection],
      arguments: .alternatives([
        [.init(.of, .matcherForSelection)],
        [.init(.matching, .matcherForSelection)],
        [.init(.outsidePaths, .stringOrStringArray)],
      ]),
      result: .violationsForSelection
    ),
  ]

  private static func stringMethod(_ name: Member) -> RuntimeMemberAPI {
    method(
      name,
      on: [.string],
      arguments: .exact([.init(nil, .exact(.string))]),
      result: .fixed(.boolean)
    )
  }

  private static func selectionStringMethod(
    _ name: Member
  ) -> RuntimeMemberAPI {
    method(
      name,
      on: [.selection],
      arguments: .unlabelledStrings,
      result: .receiver
    )
  }
}
