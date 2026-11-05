import BylawsSyntax

extension SourceListLayoutReplacement {
  static func groups(
    elements: [any SourceProviding], items: [SourceLayoutReplacement.Item],
    operations: [SourceListLayoutOperation], tree: SourceFileSyntax,
    context: SourceLayoutReplacement.Context,
    when condition: SourceLayoutCondition? = nil
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
    var order = Array(elements.indices)
    var requests = try separatorRequests(operations)
    for (regionID, region) in regions.enumerated() {
      var destination = region.lowerBound
      var pending: SourceWhitespace?
      for (group, operation) in operations.enumerated() {
        switch operation {
        case .group:
          guard let included = groupsByRegion[regionID][group] else { continue }
          if destination > region.lowerBound, let pending {
            if let requested = requests[destination], requested != pending {
              throw SourceListLayoutError.conflictingSeparators
            }
            requests[destination] = pending
          }
          for index in included {
            order[destination] = index
            destination += 1
          }
          pending = nil
        case let .separator(whitespace):
          if whitespace == .blankLine || pending == nil { pending = whitespace }
        case .conditionalSeparator: break
        }
      }
    }
    return try layoutRegions(
      elements: elements, items: items, order: order,
      regions: regions, requests: requests,
      tree: tree, context: context, condition: condition
    )
  }
}
