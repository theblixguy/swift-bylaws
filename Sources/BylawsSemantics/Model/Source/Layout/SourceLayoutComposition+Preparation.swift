import BylawsSyntax

extension SourceLayoutComposition.Session {
  func contentEdits(in edits: [SourceFix.Edit]) throws -> [SourceFix.Edit] {
    try edits.flatMap { edit in
      guard let plan = edit.layout else { return [edit] }
      let captured = try plan.thaw(snapshot: snapshot).edits
        + plan.nested.map { try $0.thaw(snapshot: snapshot) }
      return try contentEdits(in: captured)
    }
  }

  func prepare(
    _ edit: SourceFix.Edit,
    adding children: [ComposedEdit] = []
  ) throws
    -> SourceLayoutPrepared
  {
    guard let plan = edit.layout else { throw SourceError.syntaxMismatch }
    let key = ComposedEdit(edit: edit, children: children)
    if let prepared = preparedLayouts[key] { return prepared }
    let elements = try plan.elements.map {
      try SourceSlice(snapshot: snapshot, range: $0)
    }
    var prepared = try SourceLayoutReplacement.prepare(
      elements: elements, layout: plan.thaw(snapshot: snapshot),
      parsedTree: tree, allowsPartialList: plan.allowsPartialList,
      baseIndentation: plan.baseIndentation,
      nested: try plan.nested.map { try $0.thaw(snapshot: snapshot) },
      children: children,
      session: self, whenLineExceeds: plan.lineWidthLimit,
      lineEnding: lineEnding
    )
    if plan.trimmed {
      guard let first = elements.min(by: {
        $0.range.lowerBound < $1.range.lowerBound
      }), let last = elements.max(by: {
        $0.range.lowerBound < $1.range.lowerBound
      }) else { throw SourceError.syntaxMismatch }
      let lower = try SourceLayoutReplacement.Item(
        source: first, tree: tree, validatesTrailingTrivia: false
      ).contentRange.lowerBound
      let upper = try SourceLayoutReplacement.Item(
        source: last, tree: tree, validatesTrailingTrivia: false
      ).node.endPositionBeforeTrailingTrivia.utf8Offset
      guard edit.source.range == (lower..<upper)
      else { throw SourceError.syntaxMismatch }
      prepared.trimmed = true
    } else if prepared.source.range != edit.source.range {
      throw SourceError.syntaxMismatch
    }
    preparedLayouts[key] = prepared
    return prepared
  }

  func prepareContent(
    _ source: SourceSlice, applying edits: [SourceFix.Edit],
    adding children: [ComposedEdit] = []
  )
    throws -> SourceLayoutContent
  {
    let roots = try composeTree(
      edits: edits + children.flatMap(\.flattenedEdits), validating: false
    )
    guard roots.allSatisfy({
      $0.edit.source.range.lowerBound >= source.range.lowerBound
        && $0.edit.source.range.upperBound <= source.range.upperBound
    }) else { throw SourceError.rangeOutOfBounds }
    let baseline = try source.replacement(applying: contentEdits(
      in: roots.flatMap(\.flattenedEdits)
    ))
    .replacement
    let changes = try roots.map { node -> SourceLayoutContent.Change in
      let edit = node.edit
      let value: SourceLayoutContent.Change.Value = if edit.layout != nil {
        try .layout(prepare(edit, adding: node.children))
      } else { .text(edit.replacement) }
      return .init(range: edit.source.range, value: value)
    }
    return SourceLayoutContent(
      source: source,
      originalIndentation: SourceLayoutText.indentation(
        in: bytes, before: source.range.lowerBound
      ),
      baseline: baseline, changes: changes
    )
  }
}
