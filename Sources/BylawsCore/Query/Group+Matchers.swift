public import BylawsSemantics

extension Group {
  /// Groups elements that satisfy the matcher.
  public init(_ matcher: Matcher<Element>) {
    self.init { matcher($0) }
  }
}
