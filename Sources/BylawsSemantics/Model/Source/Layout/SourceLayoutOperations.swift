/// Source elements kept on one physical line.
public struct Line: Sendable {
  package let layout: SourceLayout

  /// Creates a line from the supplied source elements.
  public init(@SourceLayoutBuilder _ content: () throws
    -> SourceLayout) rethrows
  {
    layout = SourceLayout(node: .line(try content().node))
  }
}

/// Source with one extra indentation level after a line break.
public struct Indent: Sendable {
  package let layout: SourceLayout

  /// Creates a layout with indented lines.
  ///
  /// A requested line break before the first element uses the added indentation.
  /// An element that stays on its current line keeps its starting column.
  public init(@SourceLayoutBuilder _ content: () throws
    -> SourceLayout) rethrows
  {
    layout = SourceLayout(node: .indent(try content().node))
  }
}

/// Source that breaks between elements to fit a line width.
public struct Wrap: Sendable {
  package let layout: SourceLayout

  /// Creates a wrapping layout with a width of 100 characters by default.
  public init(
    width: Int? = nil,
    @SourceLayoutBuilder _ content: () throws -> SourceLayout
  ) rethrows {
    layout = SourceLayout(node: .wrap(width: width, try content().node))
  }
}

/// A position that becomes a space or a line break within a wrapping layout.
public struct Break: Sendable {
  /// Creates an optional line break.
  public init() {}
}

/// Source whose continuation lines align with its starting column.
public struct Align: Sendable {
  package let layout: SourceLayout

  /// Creates a layout with aligned continuation lines.
  public init(@SourceLayoutBuilder _ content: () throws
    -> SourceLayout) rethrows
  {
    layout = SourceLayout(node: .align(try content().node))
  }
}
