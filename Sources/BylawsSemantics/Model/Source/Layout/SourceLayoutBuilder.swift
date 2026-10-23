/// Builds a layout from captured source and layout operations.
@resultBuilder
public enum SourceLayoutBuilder {
  /// Combines the layouts in their written order.
  public static func buildBlock(_ components: SourceLayout...) -> SourceLayout {
    SourceLayout(node: .sequence(components.map(\.node)))
  }

  /// Emits one captured source element.
  public static func buildExpression(_ source: some SourceProviding)
    -> SourceLayout
  {
    SourceLayout(node: .source(source))
  }

  /// Emits captured source elements in collection order.
  public static func buildExpression<S: Sequence>(_ sources: S) -> SourceLayout
    where S.Element: SourceProviding
  {
    SourceLayout(node: .sequence(sources.map { .source($0) }))
  }

  /// Emits a source replacement within the enclosing layout.
  public static func buildExpression(_ edit: SourceFix.Edit) -> SourceLayout {
    SourceLayout(node: .edit(edit))
  }

  /// Emits an existing layout.
  public static func buildExpression(_ layout: SourceLayout)
    -> SourceLayout { layout }

  /// Emits a line of source.
  public static func buildExpression(_ line: Line) -> SourceLayout { line
    .layout
  }

  /// Emits a blank line between non-empty output.
  public static func buildExpression(_: BlankLine<Never>) -> SourceLayout {
    SourceLayout(node: .blankLine)
  }

  /// Emits a required line break.
  public static func buildExpression(_: Newline<Never>) -> SourceLayout {
    SourceLayout(node: .newline)
  }

  /// Emits indented source.
  public static func buildExpression(_ indent: Indent) -> SourceLayout { indent
    .layout
  }

  /// Emits source with optional line breaks.
  public static func buildExpression(_ wrap: Wrap) -> SourceLayout { wrap
    .layout
  }

  /// Emits an optional line break.
  public static func buildExpression(_: Break) -> SourceLayout {
    SourceLayout(node: .softBreak)
  }

  /// Emits source with aligned continuation lines.
  public static func buildExpression(_ align: Align) -> SourceLayout { align
    .layout
  }

  /// Emits a conditional layout when present.
  public static func buildOptional(_ component: SourceLayout?) -> SourceLayout {
    component ?? SourceLayout(node: .sequence([]))
  }

  /// Emits the first conditional branch.
  public static func buildEither(first component: SourceLayout)
    -> SourceLayout { component }

  /// Emits the second conditional branch.
  public static func buildEither(second component: SourceLayout)
    -> SourceLayout { component }

  /// Combines the layouts produced by a loop.
  public static func buildArray(_ components: [SourceLayout]) -> SourceLayout {
    SourceLayout(node: .sequence(components.map(\.node)))
  }

  /// Emits a layout from an availability branch.
  public static func buildLimitedAvailability(_ component: SourceLayout)
    -> SourceLayout
  {
    component
  }
}
