import BylawsSyntax

extension SourceListLayoutReplacement {
  static func groups(
    elements: [any SourceProviding], items: [SourceLayoutReplacement.Item],
    operations: [SourceListLayoutOperation], tree: SourceFileSyntax,
    context: SourceLayoutReplacement.Context
  ) throws -> SourceFix {
    var membership = [Int?](repeating: nil, count: elements.count)
    for (group, operation) in operations.enumerated() {
      guard case let .group(indices) = operation else { continue }
      for index in indices {
        guard elements.indices.contains(index)
        else { throw SourceError.syntaxMismatch }
        if membership[index] == nil { membership[index] = group }
      }
    }
    let regions = regions(membership: membership.map { $0 != nil })
    var regionIDs = [Int](repeating: -1, count: elements.count)
    for (regionID, region) in regions.enumerated() {
      for index in region { regionIDs[index] = regionID }
    }
    var groupsByRegion = [[Int: [Int]]](repeating: [:], count: regions.count)
    for (group, operation) in operations.enumerated() {
      guard case let .group(indices) = operation else { continue }
      for index in indices where membership[index] == group {
        groupsByRegion[regionIDs[index]][group, default: []].append(index)
      }
    }
    var edits: [SourceFix.Edit] = []
    var candidates: [SourceFix.Edit] = []
    for (regionID, region) in regions.enumerated() {
      var nodes: [SourceLayout.Node] = []
      var pending: SourceWhitespace?
      for (group, operation) in operations.enumerated() {
        switch operation {
        case .group:
          guard let included = groupsByRegion[regionID][group] else { continue }
          if !nodes.isEmpty, let pending {
            nodes.append(pending == .blankLine ? .blankLine : .newline)
          }
          nodes.append(contentsOf: included.map { .source(elements[$0]) })
          pending = nil
        case let .separator(whitespace):
          if whitespace == .blankLine || pending == nil { pending = whitespace }
        case .conditionalSeparator: throw SourceListLayoutError.mixedPolicies
        }
      }
      let edit = try SourceLayoutReplacement.make(
        elements: Array(elements[region]),
        layout: SourceLayout(node: .sequence(nodes)),
        parsedTree: tree, allowsPartialList: true,
        sourceContext: context,
        baseIndentation: context.indentation(
          before: items[region.lowerBound].contentRange.lowerBound
        )
      )
      let content = edit.replacement.drop(while: isWhitespace).reversed()
        .drop(while: isWhitespace).reversed()
      let source = try SourceSlice(
        snapshot: items[region.lowerBound].source.snapshot,
        range: items[region.lowerBound].contentRange
          .lowerBound..<items[region.upperBound - 1].node
          .endPositionBeforeTrailingTrivia.utf8Offset
      )
      let replacement = String(content)
      let plan = edit.layout.map {
        SourceLayoutPlan(
          elements: $0.elements, node: $0.node,
          allowsPartialList: $0.allowsPartialList,
          baseIndentation: $0.baseIndentation,
          targetRange: source.range, trimmed: true,
          lineWidthLimit: $0.lineWidthLimit, nested: $0.nested
        )
      }
      let grouped = SourceFix.Edit(
        source: source,
        replacement: replacement,
        layout: plan
      )
      if source.text.utf8.elementsEqual(replacement.utf8) {
        candidates.append(grouped)
      } else {
        edits.append(grouped)
      }
    }
    return SourceFix(edits: edits, layoutCandidates: candidates)
  }
}
