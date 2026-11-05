public import BylawsSemantics

extension Layout {
  /// Includes contained corrections when this layout applies.
  ///
  /// Each correction must come from the same captured source and remain inside
  /// one of the layout's elements. The closure is evaluated even when a condition
  /// does not match at the layout's current position.
  public func applying(
    @SourceCorrectionBuilder _ changes: () throws
      -> some SourceCorrectionProviding
  ) throws -> Self {
    try applying(changes())
  }
}
