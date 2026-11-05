/// Source elements separated by line breaks, including multiline elements.
public struct Lines: SourceLayoutProviding {
  /// The line breaks before and after the enclosed source.
  public enum Boundaries: Sendable, Hashable {
    /// Retains the source list's outer whitespace.
    case preserved
    /// Starts and ends the enclosed source on separate lines.
    case newline
  }

  /// The source arrangement described by the operation.
  public let layout: SourceLayout

  /// Separates captured source elements with line breaks.
  ///
  /// Empty content adds no boundary line breaks.
  public init<S: Sequence>(
    _ sources: S, boundaries: Boundaries = .preserved
  ) where S.Element: SourceProviding {
    self.init(layout: SourceLayout(sources), boundaries: boundaries)
  }

  /// Separates emitted elements with line breaks.
  public init(
    boundaries: Boundaries = .preserved,
    @SourceLayoutBuilder _ content: () throws -> SourceLayout
  ) rethrows {
    self.init(layout: try content(), boundaries: boundaries)
  }

  /// Separates the elements of a stored layout with line breaks.
  public init(layout: SourceLayout, boundaries: Boundaries = .preserved) {
    self.layout = SourceLayout(node: boundaries == .newline
      ? .boundedLines(layout.node) : .lines(layout.node))
  }

  /// Separates the elements of a stored layout component with line breaks.
  public init(
    layout: some SourceLayoutProviding, boundaries: Boundaries = .preserved
  ) {
    self.init(layout: layout.layout, boundaries: boundaries)
  }
}
