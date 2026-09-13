final class PortableRuleSmall {
  func one(first: Bool = false, second: Bool = true) {
    if first { return }
    guard second else { return }
  }
}

final class PortableRuleLarge {
  func one() {}
  func two() {}
}
