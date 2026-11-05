/// Source elements joined with their list separators and spaces.
///
/// Multiline source keeps its line breaks. Empty content adds no spacing.
public struct Joined: SourceLayoutProviding {
  /// The source arrangement described by the operation.
  public let layout: SourceLayout

  /// Joins captured source elements in collection order.
  public init<S: Sequence>(_ sources: S) where S.Element: SourceProviding {
    self.init(layout: SourceLayout(sources))
  }

  /// Joins emitted elements as one unit within an enclosing layout.
  public init(@SourceLayoutBuilder _ content: () throws
    -> SourceLayout) rethrows
  {
    self.init(layout: try content())
  }

  /// Joins the elements of a stored layout.
  public init(layout: SourceLayout) {
    self.layout = SourceLayout(node: .joined(layout.node))
  }

  /// Joins the elements of a stored layout component.
  public init(layout: some SourceLayoutProviding) {
    self.init(layout: layout.layout)
  }
}
