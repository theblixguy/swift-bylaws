import BylawsSyntax

package enum SourceLayoutComposition {
  package enum Failure: Error, CustomStringConvertible {
    case replacementMismatch
    case changedCandidate

    package var description: String {
      switch self {
      case .replacementMismatch:
        "SourceLayout must produce its recorded replacement. Run the rule again."
      case .changedCandidate:
        "SourceLayout context must preserve the original bytes. Report a changed layout as a correction."
      }
    }
  }

  package static func validate(_ edit: SourceFix.Edit) throws {
    guard edit.layout != nil else { return }
    try Session(snapshot: edit.source.snapshot).validate(edit)
  }

  package static func compose(
    edits: [SourceFix.Edit], candidates: [SourceFix.Edit] = []
  ) throws -> [SourceFix.Edit] {
    let groups = Dictionary(grouping: edits, by: { $0.source.snapshot })
    return try groups.keys.sorted { $0.filePath < $1.filePath }.flatMap {
      snapshot in
      let session = Session(snapshot: snapshot)
      let context = candidates.filter { $0.source.snapshot == snapshot }
      return try session.compose(
        edits: groups[snapshot] ?? [],
        candidates: context
      )
    }
  }

  package final class Session {
    let snapshot: SourceSnapshot
    lazy var bytes = snapshot.syntaxContext?.bytes ?? Array(snapshot.text.utf8)
    lazy var lineEnding = snapshot.lineEnding
    private var parsedTree: SourceFileSyntax?

    var tree: SourceFileSyntax {
      if let parsedTree { return parsedTree }
      let parsed = snapshot.swiftLanguageMode.parse(snapshot.text)
      parsedTree = parsed
      return parsed
    }

    package convenience init(snapshot: SourceSnapshot) {
      self.init(snapshot: snapshot, tree: nil)
    }

    init(snapshot: SourceSnapshot, tree: SourceFileSyntax?) {
      self.snapshot = snapshot
      parsedTree = tree ?? snapshot.parsedTree
    }

    package func validateCandidate(_ edit: SourceFix.Edit) throws {
      guard edit.layout != nil,
            edit.source.text.utf8.elementsEqual(edit.replacement.utf8)
      else { throw Failure.changedCandidate }
      try validate(edit)
    }

    package func canContain(
      _ parent: SourceFix.Edit, _ child: SourceFix.Edit
    ) -> Bool {
      guard let plan = parent.layout,
            parent.source.snapshot == snapshot,
            child.source.snapshot == snapshot,
            parent.source.range != child.source.range,
            contains(parent.source.range, child.source.range)
      else { return false }
      return (try? owns(child, plan: plan)) == true
    }

    package func validate(_ edit: SourceFix.Edit) throws {
      guard edit.source.snapshot == snapshot else {
        throw SourceError.differentSnapshots
      }
      guard let plan = edit.layout else { return }
      try plan.validate(source: edit.source)
      let layout = try plan.thaw(snapshot: snapshot)
      let nested = try plan.nested.map { try $0.thaw(snapshot: snapshot) }
      for child in nested {
        guard try owns(child, plan: plan)
        else { throw SourceError.overlappingEdits }
      }
      for child in layout.edits + nested {
        try validate(child)
      }
      guard try render(edit).utf8.elementsEqual(edit.replacement.utf8) else {
        throw Failure.replacementMismatch
      }
    }

    func compose(
      edits: [SourceFix.Edit], candidates: [SourceFix.Edit] = [],
      validating: Bool = true
    ) throws -> [SourceFix.Edit] {
      for candidate in candidates {
        guard candidate.layout != nil,
              candidate.source.text.utf8
                .elementsEqual(candidate.replacement.utf8)
        else { throw Failure.changedCandidate }
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
          && (edits.contains { intersects(
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
              !intersects(input[parent].source.range, edit.source.range)
        {
          stack.removeLast()
        }
        if let parent = stack.last {
          let outer = input[parent]
          guard outer.source.range != edit.source.range,
                contains(outer.source.range, edit.source.range),
                let plan = outer.layout,
                try owns(edit, plan: plan)
          else { throw SourceError.overlappingEdits }
          children[parent].append(index)
        } else {
          roots.append(index)
        }
        stack.append(index)
      }
      func combined(_ index: Int) throws -> SourceFix.Edit {
        let edit = input[index]
        guard let plan = edit.layout,
              !children[index].isEmpty else { return edit }
        let nested = try children[index]
          .map { SourceLayoutPlan.CapturedEdit(try combined($0)) }
        let combinedPlan = SourceLayoutPlan(
          elements: plan.elements, node: plan.node,
          allowsPartialList: plan.allowsPartialList,
          baseIndentation: plan.baseIndentation, targetRange: plan.targetRange,
          trimmed: plan.trimmed, lineWidthLimit: plan.lineWidthLimit,
          nested: plan.nested + nested
        )
        let pending = SourceFix.Edit(
          source: edit.source, replacement: edit.replacement,
          layout: combinedPlan
        )
        return SourceFix.Edit(
          source: edit.source, replacement: try render(pending),
          layout: combinedPlan
        )
      }
      return try roots.map(combined)
    }

    private func sharesLine(
      _ candidate: SourceFix.Edit,
      with edit: SourceFix.Edit
    ) -> Bool {
      var start = candidate.source.range.lowerBound
      while start > 0, bytes[start - 1] != 10,
            bytes[start - 1] != 13 { start -= 1 }
      var end = candidate.source.range.upperBound
      let endsWithLineBreak = end > start &&
        (bytes[end - 1] == 10 || bytes[end - 1] == 13)
      if !endsWithLineBreak {
        while end < bytes.count, bytes[end] != 10, bytes[end] != 13 { end += 1 }
      }
      let line = start..<end
      return line.overlaps(edit.source.range)
        || edit.source.range.isEmpty
        && (line.contains(edit.source.range.lowerBound)
          || !endsWithLineBreak && edit.source.range.lowerBound == end)
    }

    func owns(_ edit: SourceFix.Edit, plan: SourceLayoutPlan) throws -> Bool {
      guard !edit.source.range.isEmpty
        || edit.source.range.lowerBound > plan.targetRange.lowerBound
        && edit.source.range.upperBound < plan.targetRange.upperBound
      else { return false }
      return try plan.elements.contains { range in
        let item = try SourceLayoutReplacement.Item(
          source: SourceSlice(snapshot: snapshot, range: range), tree: tree,
          validatesTrailingTrivia: false
        )
        return contains(item.contentRange, edit.source.range)
      }
    }
  }

  private static func contains(
    _ outer: Range<Int>,
    _ inner: Range<Int>
  ) -> Bool {
    outer.lowerBound <= inner.lowerBound && outer.upperBound >= inner.upperBound
  }

  private static func intersects(_ lhs: Range<Int>, _ rhs: Range<Int>) -> Bool {
    lhs.overlaps(rhs)
      || lhs.isEmpty && rhs.contains(lhs.lowerBound)
      || rhs.isEmpty && lhs.contains(rhs.lowerBound)
      || lhs.isEmpty && rhs.isEmpty && lhs.lowerBound == rhs.lowerBound
  }
}
