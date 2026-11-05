import BylawsSyntax

extension SourceLayoutComposition.Session {
  func contentEdits(in edits: [SourceFix.Edit]) throws -> [SourceFix.Edit] {
    try edits.flatMap { edit in
      guard let plan = edit.layout else { return [edit] }
      let captured = try plan.resolve(snapshot: snapshot).edits
        + (plan.formatting?.nested ?? [])
        .filter { $0.ownership == .independent }
        .map { try $0.resolve(snapshot: snapshot) }
      return try contentEdits(in: captured)
    }
  }

  func prepare(
    _ edit: SourceFix.Edit,
    adding children: [ComposedEdit] = []
  ) throws
    -> SourceLayoutPrepared
  {
    guard edit.layout != nil else { throw SourceError.syntaxMismatch }
    let key = ComposedEdit(edit: edit, children: children)
    if children.isEmpty { return try prepareLayout(key) }
    if let prepared = preparedLayouts[key] { return prepared }
    var pending: [(key: ComposedEdit, childrenScheduled: Bool)] = [(key, false)]
    while let frame = pending.popLast() {
      guard frame.key.edit.layout != nil,
            preparedLayouts[frame.key] == nil else { continue }
      if frame.childrenScheduled {
        _ = try prepareLayout(frame.key)
      } else {
        pending.append((frame.key, true))
        for child in frame.key.children.reversed()
          where child.edit.layout != nil
        {
          pending.append((child, false))
        }
      }
    }
    return try prepareLayout(key)
  }

  private func prepareLayout(_ key: ComposedEdit) throws
    -> SourceLayoutPrepared
  {
    if let prepared = preparedLayouts[key] { return prepared }
    let edit = key.edit
    let children = key.children
    guard let plan = edit.layout else { throw SourceError.syntaxMismatch }
    let prepared = switch plan.mode {
    case let .layout(formatting):
      try prepareFormatting(
        edit,
        plan: plan,
        formatting: formatting,
        children: children
      )
    }
    preparedLayouts[key] = prepared
    return prepared
  }

  private func prepareFormatting(
    _ edit: SourceFix.Edit, plan: SourceLayoutPlan,
    formatting: SourceLayoutPlan.Layout, children: [ComposedEdit]
  ) throws -> SourceLayoutPrepared {
    let elements = try plan.elements.map {
      try SourceSlice(snapshot: snapshot, range: $0)
    }
    var prepared = try SourceLayoutReplacement.prepare(
      elements: elements, layout: plan.resolve(snapshot: snapshot),
      parsedTree: tree, allowsPartialList: formatting.allowsPartialList,
      baseIndentation: formatting.baseIndentation,
      nested: try formatting.nested.filter { $0.ownership == .independent }
        .map { try $0.resolve(snapshot: snapshot) },
      attached: try formatting.nested.filter { $0.ownership == .withLayout }
        .map { try $0.resolve(snapshot: snapshot) },
      children: children,
      session: self, when: formatting.condition,
      lineEnding: lineEnding
    )
    if formatting.trimmed {
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
      prepared.source = edit.source
      prepared.capture = plan
      prepared.trimmed = true
    } else if prepared.source.range != edit.source.range {
      throw SourceError.syntaxMismatch
    }
    return prepared
  }

  func prepareContent(
    _ source: SourceSlice, applying edits: [SourceFix.Edit],
    adding children: [ComposedEdit] = []
  )
    throws -> SourceLayoutContent
  {
    if edits.isEmpty, children.isEmpty {
      return SourceLayoutContent(
        source: source,
        originalIndentation: SourceLayoutText.indentation(
          in: bytes, before: source.range.lowerBound
        ),
        baseline: source.text, changes: []
      )
    }
    let roots = if edits.isEmpty {
      children
    } else {
      try composeTree(
        edits: edits + children.flatMap(\.flattenedEdits), validating: false
      )
    }
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
