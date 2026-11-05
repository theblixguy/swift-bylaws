extension Layout {
  /// Arranges a source list with a stored layout component.
  public init(
    _ elements: some Collection<Element>,
    layout: some SourceLayoutProviding,
    when condition: SourceLayoutCondition? = nil
  ) throws {
    try self.init(elements, layout: layout.layout, when: condition)
  }
}

extension Collection where Element: SourceProviding {
  /// Returns a list replacement using a stored layout component.
  public func replacement(
    layout: some SourceLayoutProviding,
    when condition: SourceLayoutCondition? = nil
  ) throws -> SourceFix.Edit {
    try replacement(layout: layout.layout, when: condition)
  }
}
