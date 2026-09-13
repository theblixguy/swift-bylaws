extension SupportedAPI.ArgumentContract {
  func accepts(labels: [String?]) -> Bool {
    switch self {
    case .none: labels.isEmpty
    case let .strings(label): labels.equal(leading: label)
    case let .oneString(label): labels.equal([label])
    case let .optionalStringArray(label): labels.equal([label])
    case .functionParameter:
      labels.equal([.typed]) || labels.equal([.labelled])
        || labels.equal(leading: .referencing)
    case .visibility: labels.equal([.atLeast])
    }
  }
}

extension [String?] {
  fileprivate func equal(leading label: SupportedAPI.ArgumentLabel?) -> Bool {
    let unlabelled = [SupportedAPI.ArgumentLabel?](
      repeating: nil,
      count: Swift.max(count - 1, 0)
    )
    return equal([label] + unlabelled)
  }
}
