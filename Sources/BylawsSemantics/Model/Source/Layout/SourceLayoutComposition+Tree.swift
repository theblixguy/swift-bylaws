extension SourceLayoutComposition.Session {
  struct ComposedEdit: Hashable {
    let edit: SourceFix.Edit
    let children: [ComposedEdit]

    var flattenedEdits: [SourceFix.Edit] {
      [edit] + children.flatMap(\.flattenedEdits)
    }
  }

  func composeTree(
    edits: [SourceFix.Edit], candidates: [SourceFix.Edit] = [],
    validating: Bool = true
  ) throws -> [ComposedEdit] {
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
    func composed(_ index: Int) -> ComposedEdit {
      ComposedEdit(edit: input[index], children: children[index].map(composed))
    }
    return roots.map(composed)
  }
}
