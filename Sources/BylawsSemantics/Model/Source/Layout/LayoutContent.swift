/// Source arrangements and policies for one captured list.
public indirect enum LayoutContent<Element: SourceProviding>: Sendable {
  /// An explicit arrangement that retains every input element.
  case layout(source: SourceLayout)
  /// A group that takes elements not claimed by earlier groups.
  case group(Group<Element>)
  /// A newline or blank line between populated groups or explicit source.
  case separator(SourceWhitespace)
  /// A blank line between elements that match a condition.
  case blankLine(BlankLine<Element>)
  /// A line break between elements that match a condition.
  case newline(Newline<Element>)
  /// Layout components in their written order.
  case sequence([Self])

  /// Includes a stored source arrangement.
  public static func layout(_ source: SourceLayout) -> Self {
    .layout(source: source)
  }

  /// Includes the source arrangement described by a layout component.
  public static func layout(_ component: some SourceLayoutProviding) -> Self {
    .layout(source: component.layout)
  }

  package var components: [Self] {
    var result: [Self] = []
    var pending = [self]
    while let component = pending.popLast() {
      if case let .sequence(children) = component {
        pending.append(contentsOf: children.reversed())
      } else {
        result.append(component)
      }
    }
    return result
  }
}
