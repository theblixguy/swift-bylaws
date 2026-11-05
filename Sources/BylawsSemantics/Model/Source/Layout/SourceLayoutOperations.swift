/// Source elements kept on one physical line.
public struct Line: SourceLayoutProviding {
  /// The source arrangement described by the operation.
  public let layout: SourceLayout

  /// Places captured source elements on one physical line.
  public init<S: Sequence>(_ sources: S) where S.Element: SourceProviding {
    self.init(layout: SourceLayout(sources))
  }

  /// Creates a line from the supplied source elements.
  public init(@SourceLayoutBuilder _ content: () throws
    -> SourceLayout) rethrows
  {
    self.init(layout: try content())
  }

  /// Places a stored layout on one physical line.
  public init(layout: SourceLayout) {
    self.layout = SourceLayout(node: .line(layout.node))
  }

  /// Places a stored layout component on one physical line.
  public init(layout: some SourceLayoutProviding) {
    self.init(layout: layout.layout)
  }
}

/// Source with one extra indentation level after a line break.
public struct Indent: SourceLayoutProviding {
  /// The source arrangement described by the operation.
  public let layout: SourceLayout

  /// Indents the continuation lines of captured source elements.
  public init<S: Sequence>(_ sources: S) where S.Element: SourceProviding {
    self.init(layout: SourceLayout(sources))
  }

  /// Creates a layout with indented lines.
  ///
  /// A requested line break before the first element uses the added indentation.
  /// An element that stays on its current line keeps its starting column.
  public init(@SourceLayoutBuilder _ content: () throws
    -> SourceLayout) rethrows
  {
    self.init(layout: try content())
  }

  /// Indents the continuation lines of a stored layout by one level.
  public init(layout: SourceLayout) {
    self.layout = SourceLayout(node: .indent(layout.node))
  }

  /// Indents the continuation lines of a stored layout component.
  public init(layout: some SourceLayoutProviding) {
    self.init(layout: layout.layout)
  }
}

/// Source that breaks between elements to fit a line width.
public struct Wrap: SourceLayoutProviding {
  /// The source arrangement described by the operation.
  public let layout: SourceLayout

  /// Wraps captured source elements at permitted boundaries.
  public init<S: Sequence>(_ sources: S, width: Int? = nil)
    where S.Element: SourceProviding
  {
    self.init(layout: SourceLayout(sources), width: width)
  }

  /// Creates a wrapping layout with a width of 100 characters by default.
  public init(
    width: Int? = nil,
    @SourceLayoutBuilder _ content: () throws -> SourceLayout
  ) rethrows {
    self.init(layout: try content(), width: width)
  }

  /// Wraps a stored layout at permitted boundaries.
  public init(layout: SourceLayout, width: Int? = nil) {
    self.layout = SourceLayout(node: .wrap(width: width, layout.node))
  }

  /// Wraps a stored layout component at permitted boundaries.
  public init(layout: some SourceLayoutProviding, width: Int? = nil) {
    self.init(layout: layout.layout, width: width)
  }
}

/// A position that becomes a space or a line break within a wrapping layout.
public struct Break: Sendable {
  /// Creates an optional line break.
  public init() {}
}

/// Source whose continuation lines align with its starting column.
public struct Align: SourceLayoutProviding {
  /// The source arrangement described by the operation.
  public let layout: SourceLayout

  /// Aligns captured source elements with their starting column.
  public init<S: Sequence>(_ sources: S) where S.Element: SourceProviding {
    self.init(layout: SourceLayout(sources))
  }

  /// Creates a layout with aligned continuation lines.
  public init(@SourceLayoutBuilder _ content: () throws
    -> SourceLayout) rethrows
  {
    self.init(layout: try content())
  }

  /// Aligns a stored layout's continuation lines with its starting column.
  public init(layout: SourceLayout) {
    self.layout = SourceLayout(node: .align(layout.node))
  }

  /// Aligns the continuation lines of a stored layout component.
  public init(layout: some SourceLayoutProviding) {
    self.init(layout: layout.layout)
  }
}
