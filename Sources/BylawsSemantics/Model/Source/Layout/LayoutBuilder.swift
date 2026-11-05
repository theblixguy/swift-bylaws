/// Builds an arrangement or grouping and spacing policy for a source list.
@resultBuilder
public enum LayoutBuilder<Element: SourceProviding> {
  /// Combines components in their written order.
  public static func buildBlock(_ components: LayoutContent<Element>...)
    -> LayoutContent<Element>
  {
    .sequence(components)
  }

  /// Includes a stored layout component.
  public static func buildExpression(_ component: LayoutContent<Element>)
    -> LayoutContent<Element>
  {
    component
  }

  /// Emits a captured source element.
  public static func buildExpression(_ source: some SourceProviding)
    -> LayoutContent<Element>
  {
    .layout(SourceLayout(node: .source(source)))
  }

  /// Emits captured source elements in collection order.
  public static func buildExpression<S: Sequence>(_ sources: S)
    -> LayoutContent<Element> where S.Element: SourceProviding
  {
    .layout(SourceLayout(node: .sequence(sources.map { .source($0) })))
  }

  /// Emits an edit within its containing source element.
  public static func buildExpression(_ edit: SourceFix.Edit)
    -> LayoutContent<Element>
  {
    .layout(SourceLayout(node: .edit(edit)))
  }

  /// Includes prepared edits from another correction operation.
  public static func buildExpression(
    _ operation: some SourceCorrectionProviding
  )
    -> LayoutContent<Element>
  {
    .layout(SourceLayout(operation))
  }

  /// Emits a stored source arrangement.
  public static func buildExpression(_ layout: SourceLayout)
    -> LayoutContent<Element> { .layout(layout) }

  /// Emits the source arrangement described by a layout component.
  public static func buildExpression(_ component: some SourceLayoutProviding)
    -> LayoutContent<Element> { .layout(component.layout) }

  /// Adds an optional line break.
  public static func buildExpression(_: Break)
    -> LayoutContent<Element> { .layout(SourceLayout(node: .softBreak)) }

  /// Adds a first-match group.
  public static func buildExpression(_ group: Group<Element>)
    -> LayoutContent<Element> { .group(group) }

  /// Adds a blank line between nonempty output.
  public static func buildExpression(_: BlankLine<Never>)
    -> LayoutContent<Element> { .separator(.blankLine) }

  /// Adds a line break between nonempty output.
  public static func buildExpression(_: Newline<Never>)
    -> LayoutContent<Element> { .separator(.newline) }

  /// Adds a conditional blank line between adjacent elements.
  public static func buildExpression(_ line: BlankLine<Element>)
    -> LayoutContent<Element> { .blankLine(line) }

  /// Adds a conditional line break between adjacent elements.
  public static func buildExpression(_ line: Newline<Element>)
    -> LayoutContent<Element> { .newline(line) }

  /// Includes a component when its condition is true.
  public static func buildOptional(_ component: LayoutContent<Element>?)
    -> LayoutContent<Element> { component ?? .sequence([]) }

  /// Includes the first branch of a condition.
  public static func buildEither(first component: LayoutContent<Element>)
    -> LayoutContent<Element> { component }

  /// Includes the second branch of a condition.
  public static func buildEither(second component: LayoutContent<Element>)
    -> LayoutContent<Element> { component }

  /// Combines the components produced by a loop.
  public static func buildArray(_ components: [LayoutContent<Element>])
    -> LayoutContent<Element> { .sequence(components) }

  /// Includes a component for an available API.
  public static func buildLimitedAvailability(
    _ component: LayoutContent<Element>
  )
    -> LayoutContent<Element> { component }
}
