extension SourceLayoutComposition.Session {
  struct ComposedEdit: Hashable {
    let edit: SourceFix.Edit
    let children: [ComposedEdit]

    var flattenedEdits: [SourceFix.Edit] {
      guard !children.isEmpty else { return [edit] }
      var result: [SourceFix.Edit] = []
      var pending = [self]
      while let node = pending.popLast() {
        result.append(node.edit)
        pending.append(contentsOf: node.children.reversed())
      }
      return result
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
      guard lhs.edit == rhs.edit,
            lhs.children.count == rhs.children.count else { return false }
      guard !lhs.children.isEmpty else { return true }
      var pending = lhs.children.indices.map { (
        lhs.children[$0],
        rhs.children[$0]
      ) }
      while let (left, right) = pending.popLast() {
        guard left.edit == right.edit,
              left.children.count == right.children.count else { return false }
        for index in left.children.indices {
          pending.append((left.children[index], right.children[index]))
        }
      }
      return true
    }

    func hash(into hasher: inout Hasher) {
      hasher.combine(edit)
      hasher.combine(children.count)
      guard !children.isEmpty else { return }
      var pending = Array(children.reversed())
      while let node = pending.popLast() {
        hasher.combine(node.edit)
        hasher.combine(node.children.count)
        pending.append(contentsOf: node.children.reversed())
      }
    }
  }

  func composeTree(
    edits: [SourceFix.Edit], candidates: [SourceFix.Edit] = [],
    validating: Bool = true
  ) throws -> [ComposedEdit] {
    if validating {
      preparedLayouts.reserveCapacity(candidates.count + edits.count(where: {
        $0.layout != nil
      }))
    }
    for candidate in candidates {
      guard candidate.layout != nil,
            candidate.source.text.utf8
              .elementsEqual(candidate.replacement.utf8)
      else { throw SourceLayoutComposition.Failure.changedCandidate }
      if validating { try validate(candidate) }
    }
    let active = Set(edits)
    let candidateSet = Set(candidates)
    let changesLines = try contentEdits(in: edits).contains {
      $0.source.text.contains(where: SourceLayoutText.isNewline)
        || $0.replacement.contains(where: SourceLayoutText.isNewline)
    }
    let context = Array(candidateSet).filter { candidate in
      !active.contains(candidate)
        && (edits.contains { SourceLayoutComposition.intersects(
          candidate.source.range,
          $0.source.range
        ) }
          || candidate.layout?.lineWidthLimit != nil
          &&
          (changesLines || edits
            .contains { sharesLine(candidate, with: $0) }))
    }
    let input = (edits + context).sorted {
      if $0.source.range.lowerBound != $1.source.range.lowerBound {
        return $0.source.range.lowerBound < $1.source.range.lowerBound
      }
      return $0.source.range.upperBound > $1.source.range.upperBound
    }
    var children = [[Int]](repeating: [], count: input.count)
    var roots: [Int] = []
    var stack: [Int] = []
    for index in input.indices {
      let edit = input[index]
      guard edit.source.snapshot == snapshot else {
        throw SourceError.differentSnapshots
      }
      if validating, !candidateSet.contains(edit) { try validate(edit) }
      while let parent = stack.last,
            !SourceLayoutComposition.intersects(
              input[parent].source.range,
              edit.source.range
            )
      {
        stack.removeLast()
      }
      if let parent = stack.last {
        let outer = input[parent]
        guard outer.source.range != edit.source.range,
              SourceLayoutComposition.contains(
                outer.source.range,
                edit.source.range
              ),
              let plan = outer.layout,
              try owns(edit, plan: plan)
        else { throw SourceError.overlappingEdits }
        children[parent].append(index)
      } else {
        roots.append(index)
      }
      stack.append(index)
    }
    var composed = input.map { ComposedEdit(edit: $0, children: []) }
    for index in input.indices.reversed() where !children[index].isEmpty {
      composed[index] = ComposedEdit(
        edit: input[index], children: children[index].map { composed[$0] }
      )
    }
    return roots.map { composed[$0] }
  }
}
