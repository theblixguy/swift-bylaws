import BylawsSyntax

extension Collection where Element: SourceProviding {
  /// Returns corrections that group elements or change matching gaps.
  ///
  /// The first matching group claims each element. Unmatched elements divide
  /// the input into regions that groups cannot cross. Conditional separators
  /// change matching gaps and preserve all other whitespace. Empty input
  /// produces no edits. Grouped regions retain their original indentation.
  /// To arrange source elements explicitly, use the ``SourceLayoutBuilder``
  /// overload.
  ///
  /// Errors from the layout closure, conditions and comparisons propagate.
  /// - Throws: ``SourceListLayoutError`` for conflicting policies, or the
  ///   source and ownership errors of ``SourceLayoutReplacementError``.
  public func replacement(
    @SourceListLayoutBuilder<Element> _ layout: () throws
      -> SourceListLayout<Element>
  ) throws -> SourceFix {
    let elements = Array(self)
    let directives = try layout().directives
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
      case let .separator(whitespace): operations.append(.separator(whitespace))
      case let .conditional(separator, whitespace):
        var gaps = Set<Int>()
        for index in elements.indices.dropFirst() {
          if try separator.matches(
            previous: elements[index - 1],
            next: elements[index]
          ) {
            gaps.insert(index)
          }
        }
        operations.append(.conditionalSeparator(
          gaps: gaps,
          whitespace: whitespace
        ))
      }
    }
    var regionIDs = [Int](repeating: -1, count: elements.count)
    for (regionID, region) in SourceListLayoutReplacement
      .regions(membership: claimed).enumerated()
    {
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
          elements[$0],
          elements[$1]
        ) }
        start = end
      }
      operations[operationIndex] = .group(indices: ordered)
    }
    return try SourceListLayoutReplacement.make(
      elements: elements,
      operations: operations
    )
  }
}

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

  package static func make(
    elements: [any SourceProviding], operations: [SourceListLayoutOperation]
  ) throws -> SourceFix {
    let hasGroups = operations
      .contains { if case .group = $0 { true } else { false } }
    let hasConditions = operations
      .contains { if case .conditionalSeparator = $0 { true } else { false } }
    guard !hasGroups || !hasConditions
    else { throw SourceListLayoutError.mixedPolicies }
    guard !elements.isEmpty else { return SourceFix(edits: []) }
    let slices = try elements.map { try $0.source }
    guard let first = slices.first else { return SourceFix(edits: []) }
    guard slices.allSatisfy({ $0.snapshot == first.snapshot }) else {
      throw SourceLayoutReplacementError.differentSnapshots
    }
    let snapshot = first.snapshot
    let tree = snapshot.parsedTree
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
    if hasGroups {
      return try groups(
        elements: elements,
        items: items,
        operations: operations,
        tree: tree,
        context: SourceLayoutReplacement.Context(
          snapshot: snapshot, bytes: bytes, excluding: list.range
        )
      )
    }
    return try separators(items: items, operations: operations)
  }
}
