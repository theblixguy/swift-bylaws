extension SupportedAPI.ArgumentLabel? {
  var written: String? { self?.rawValue }
}

extension [String?] {
  func equal(_ labels: [SupportedAPI.ArgumentLabel?]) -> Bool {
    self == labels.map(\.written)
  }

  func contains(_ label: SupportedAPI.ArgumentLabel) -> Bool {
    contains(label.rawValue)
  }
}
