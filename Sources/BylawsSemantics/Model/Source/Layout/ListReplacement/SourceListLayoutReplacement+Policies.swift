extension SourceListLayoutReplacement {
  static func make<Element: SourceProviding>(
    elements: [Element], layout: SourceListLayout<Element>,
    when condition: SourceLayoutCondition? = nil
  ) throws -> SourceFix {
    let directives = layout.directives
    var claimed = [Bool](repeating: false, count: elements.count)
    var operations: [SourceListLayoutOperation] = []
    for directive in directives {
      switch directive {
      case let .group(group):
        var indices: [Int] = []
        for index in elements.indices where !claimed[index] {
          if try group.predicate(elements[index]) {
            indices.append(index)
            claimed[index] = true
          }
        }
        operations.append(.group(indices: indices))
      case let .separator(whitespace):
        operations.append(.separator(whitespace))
      case let .conditional(_, whitespace):
        operations.append(.conditionalSeparator(
          gaps: [],
          whitespace: whitespace
        ))
      }
    }
    let regions = regions(membership: claimed)
    var regionIDs = [Int](repeating: -1, count: elements.count)
    for (regionID, region) in regions.enumerated() {
      for index in region { regionIDs[index] = regionID }
    }
    for (operationIndex, directive) in directives.enumerated() {
      guard case let .group(group) = directive,
            let comparison = group.comparison,
            case let .group(indices) = operations[operationIndex]
      else { continue }
      var ordered: [Int] = []
      var start = 0
      while start < indices.count {
        var end = start + 1
        while end < indices.count,
              regionIDs[indices[end]] == regionIDs[indices[start]] { end += 1 }
        ordered += try indices[start..<end].sorted { try comparison(
          elements[$0], elements[$1]
        ) }
        start = end
      }
      operations[operationIndex] = .group(indices: ordered)
    }
    let order = orderedIndices(
      operations: operations, regions: regions, regionIDs: regionIDs
    )
    for (operationIndex, directive) in directives.enumerated() {
      guard case let .conditional(separator, whitespace) = directive
      else { continue }
      var gaps = Set<Int>()
      for index in order.indices.dropFirst() {
        if try separator.matches(
          previous: elements[order[index - 1]], next: elements[order[index]]
        ) { gaps.insert(index) }
      }
      operations[operationIndex] = .conditionalSeparator(
        gaps: gaps, whitespace: whitespace
      )
    }
    return try make(
      elements: elements, operations: operations, when: condition
    )
  }
}
