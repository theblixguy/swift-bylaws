import BylawsSyntax

package enum SourceListLayoutOperation: Sendable {
  case group(indices: [Int])
  case separator(SourceWhitespace)
  case conditionalSeparator(gaps: Set<Int>, whitespace: SourceWhitespace)
}

package enum SourceListLayoutReplacement {
  package static func regions(membership: [Bool]) -> [Range<Int>] {
    var result: [Range<Int>] = []
    var start = 0
    while start < membership.count {
      guard membership[start] else {
        start += 1
        continue
      }
      var end = start + 1
      while end < membership.count, membership[end] { end += 1 }
      result.append(start..<end)
      start = end
    }
    return result
  }

  package static func orderedIndices(
    operations: [SourceListLayoutOperation],
    regions: [Range<Int>], regionIDs: [Int]
  ) -> [Int] {
    var order = Array(regionIDs.indices)
    var positions = regions.map(\.lowerBound)
    for operation in operations {
      guard case let .group(indices) = operation else { continue }
      for index in indices {
        let regionID = regionIDs[index]
        order[positions[regionID]] = index
        positions[regionID] += 1
      }
    }
    return order
  }

  package static func make(
    elements: [any SourceProviding], operations: [SourceListLayoutOperation],
    when condition: SourceLayoutCondition? = nil
  ) throws -> SourceFix {
    guard !elements.isEmpty else { return SourceFix(edits: []) }
    let hasGroups =
      operations
        .contains { if case .group = $0 { true } else { false } }
    let slices = try elements.map { try $0.source }
    guard let first = slices.first else { return SourceFix(edits: []) }
    guard slices.allSatisfy({ $0.snapshot == first.snapshot }) else {
      throw SourceLayoutReplacementError.differentSnapshots
    }
    let snapshot = first.snapshot
    let tree =
      snapshot.parsedTree
        ?? snapshot.syntaxTree()
    let items = try slices.map {
      try SourceLayoutReplacement.Item(
        source: $0,
        tree: tree,
        validatesTrailingTrivia: false
      )
    }
    guard zip(items, items.dropFirst())
      .allSatisfy({ $0.node.position < $1.node.position })
    else {
      throw SourceLayoutReplacementError.noncontiguousElements
    }
    let bytes = snapshot.syntaxContext?.bytes ?? Array(snapshot.text.utf8)
    let list = try SourceLayoutReplacement.List(
      items: items, snapshot: snapshot, sourceBytes: bytes
    )
    let context = SourceLayoutReplacement.Context(
      snapshot: snapshot, bytes: bytes, excluding: list.range
    )
    if hasGroups {
      return try groups(
        elements: elements,
        items: items,
        operations: operations,
        tree: tree,
        context: context, when: condition
      )
    }
    if let condition {
      return try spacedRegions(
        elements: elements, items: items,
        requests: separatorRequests(operations), tree: tree,
        context: context, condition: condition
      )
    }
    return try separators(items: items, operations: operations)
  }
}
