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

  package final class Session {
    let snapshot: SourceSnapshot
    lazy var bytes = snapshot.syntaxContext?.bytes ?? Array(snapshot.text.utf8)
    lazy var lineEnding = snapshot.lineEnding
    private var parsedTree: SourceFileSyntax?
    var preparedLayouts: [ComposedEdit: SourceLayoutPrepared] = [:]

    var tree: SourceFileSyntax {
      if let parsedTree { return parsedTree }
      let parsed = snapshot.syntaxTree()
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

    func render(
      _ edit: SourceFix.Edit,
      at placement: SourceLayoutRenderer.Placement? = nil
    ) throws -> String {
      guard edit.layout != nil else { return edit.replacement }
      return try SourceLayoutRenderer.render(prepare(edit), at: placement)
    }

    func content(
      _ source: SourceSlice, applying edits: [SourceFix.Edit],
      adding children: [ComposedEdit] = [],
      at placement: SourceLayoutRenderer.Placement,
      followedBy following: SourceLayoutContinuation = .end
    ) throws -> String {
      let content = try prepareContent(
        source, applying: edits, adding: children
      )
      return try SourceLayoutRenderer.render(
        content.document(indentation: placement.indentation),
        at: placement, followedBy: following
      )
    }

    func sharesLine(
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

  static func contains(
    _ outer: Range<Int>,
    _ inner: Range<Int>
  ) -> Bool {
    outer.lowerBound <= inner.lowerBound && outer.upperBound >= inner.upperBound
  }

  static func intersects(_ lhs: Range<Int>, _ rhs: Range<Int>) -> Bool {
    lhs.overlaps(rhs)
      || lhs.isEmpty && rhs.contains(lhs.lowerBound)
      || rhs.isEmpty && lhs.contains(rhs.lowerBound)
      || lhs.isEmpty && rhs.isEmpty && lhs.lowerBound == rhs.lowerBound
  }
}
