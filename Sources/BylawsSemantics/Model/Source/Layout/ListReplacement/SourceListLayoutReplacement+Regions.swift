import BylawsSyntax

extension SourceListLayoutReplacement {
  static func spacedRegions(
    elements: [any SourceProviding], items: [SourceLayoutReplacement.Item],
    requests: [Int: SourceWhitespace], tree: SourceFileSyntax,
    context: SourceLayoutReplacement.Context, condition: SourceLayoutCondition
  ) throws -> SourceFix {
    try layoutRegions(
      elements: elements, items: items, order: Array(elements.indices),
      regions: [], requests: requests, tree: tree, context: context,
      condition: condition
    )
  }

  static func layoutRegions(
    elements: [any SourceProviding], items: [SourceLayoutReplacement.Item],
    order: [Int], regions: [Range<Int>], requests: [Int: SourceWhitespace],
    tree: SourceFileSyntax, context: SourceLayoutReplacement.Context,
    condition: SourceLayoutCondition?
  ) throws -> SourceFix {
    let gaps = try requests.keys.map { gap -> Range<Int> in
      guard gap > 0, gap < items.count else { throw SourceError.syntaxMismatch }
      return (gap - 1)..<(gap + 1)
    }
    var edits: [SourceFix.Edit] = []
    for region in mergedRegions(regions + gaps) {
      var nodes: [SourceLayout.Node] = []
      for position in region {
        if position > region.lowerBound, let whitespace = requests[position] {
          nodes.append(whitespace == .blankLine ? .blankLine : .newline)
        }
        nodes.append(.source(elements[order[position]]))
      }
      edits.append(try regionReplacement(
        elements: Array(elements[region]), items: Array(items[region]),
        nodes: nodes, tree: tree, context: context, condition: condition
      ))
    }
    return SourceFix(proposedEdits: edits)
  }

  private static func mergedRegions(_ regions: [Range<Int>]) -> [Range<Int>] {
    var result: [Range<Int>] = []
    for region in regions.sorted(by: { $0.lowerBound < $1.lowerBound }) {
      if let previous = result.last, previous.upperBound > region.lowerBound {
        result[result.count - 1] = previous.lowerBound..<max(
          previous.upperBound, region.upperBound
        )
      } else {
        result.append(region)
      }
    }
    return result
  }

  private static func regionReplacement(
    elements: [any SourceProviding], items: [SourceLayoutReplacement.Item],
    nodes: [SourceLayout.Node], tree: SourceFileSyntax,
    context: SourceLayoutReplacement.Context, condition: SourceLayoutCondition?
  ) throws -> SourceFix.Edit {
    guard let first = items.first, let last = items.last else {
      throw SourceLayoutReplacementError.emptyCollection
    }
    var prepared = try SourceLayoutReplacement.prepare(
      elements: elements, layout: SourceLayout(node: .sequence(nodes)),
      parsedTree: tree, allowsPartialList: true, sourceContext: context,
      baseIndentation: context
        .indentation(before: first.contentRange.lowerBound),
      when: condition
    )
    let source = try SourceSlice(
      snapshot: first.source.snapshot,
      range: first.contentRange.lowerBound..<last.node
        .endPositionBeforeTrailingTrivia.utf8Offset
    )
    prepared.trimmed = true
    let capture = prepared.capture
    guard let formatting = capture.formatting
    else { throw SourceError.syntaxMismatch }
    let plan = SourceLayoutPlan(
      elements: capture.elements, node: formatting.node,
      allowsPartialList: formatting.allowsPartialList,
      baseIndentation: formatting.baseIndentation,
      targetRange: source.range, trimmed: true,
      condition: formatting.condition, nested: formatting.nested
    )
    prepared.source = source
    prepared.capture = plan
    return SourceFix.Edit(
      source: source,
      replacement: try SourceLayoutRenderer.render(prepared), layout: plan
    )
  }
}
