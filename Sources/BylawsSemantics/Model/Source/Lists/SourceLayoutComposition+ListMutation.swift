extension SourceLayoutComposition.Session {
  func prepareListMutation(
    _ edit: SourceFix.Edit, plan: SourceLayoutPlan,
    mutation: SourceListMutationPlan, children: [ComposedEdit]
  ) throws -> SourceLayoutPrepared {
    if mutation.formatsElements {
      return try prepareMutatedLayout(
        edit,
        plan: plan,
        mutation: mutation,
        children: children
      )
    }
    let ordered = try mutation.mutations.map { value in
      (mutation: value, list: try value.resolve(snapshot: snapshot))
    }.sorted {
      if $0.list.source.range.lowerBound != $1.list.source.range.lowerBound {
        return $0.list.source.range.lowerBound < $1.list.source.range.lowerBound
      }
      return $0.mutation.kind == .attributes && $1.mutation.kind == .modifiers
    }
    let sourceContext = SourceListEditing.context(for: ordered[0].list)
    var text = ""
    var cursor = edit.source.range.lowerBound
    for (index, (value, list)) in ordered.enumerated() {
      guard cursor <= list.source.range.lowerBound
      else { throw SourceError.overlappingEdits }
      text += try SourceSlice(
        snapshot: snapshot,
        range: cursor..<list.source.range.lowerBound
      ).text
      text += try value.preservingSource(
        in: list, context: index == 0 ? sourceContext : nil, session: self,
        children: children.filter {
          SourceLayoutComposition.contains(
            list.source.range,
            $0.edit.source.range
          )
        }
      )
      cursor = list.source.range.upperBound
    }
    text += try SourceSlice(
      snapshot: snapshot,
      range: cursor..<edit.source.range.upperBound
    ).text
    let indentation =
      sourceContext.indentation(before: edit.source.range.lowerBound)
    let context = SourceLayoutRenderer.Context(
      initialColumn: sourceContext.column(before: edit.source.range.lowerBound),
      initialIndentation: indentation, baseIndentation: indentation,
      indentationUnit: sourceContext.indentationUnit, lineEnding: lineEnding
    )
    let content = SourceLayoutContent(
      source: edit.source, originalIndentation: indentation,
      baseline: text,
      changes: [.init(range: edit.source.range, value: .text(text))]
    )
    return SourceLayoutPrepared(
      source: edit.source, capture: plan, content: content,
      lookaheadText: text,
      document: SourceLayoutDocument(events: [.content(content)]),
      context: context,
      originalPlacement: .init(
        column: context.initialColumn,
        indentation: indentation,
        lineIndentation: indentation
      ),
      indentsContents: false, closesOwner: false, hasBaseIndentation: false
    )
  }

  private func prepareMutatedLayout(
    _ edit: SourceFix.Edit, plan: SourceLayoutPlan,
    mutation: SourceListMutationPlan, children: [ComposedEdit]
  ) throws -> SourceLayoutPrepared {
    guard let value = mutation.mutations.first,
          mutation.mutations.count == 1
    else {
      throw SourceError.syntaxMismatch
    }
    let list = try value.resolve(snapshot: snapshot)
    let items = try list.slices().map {
      try SourceLayoutReplacement.Item(
        source: $0,
        tree: tree,
        validatesTrailingTrivia: false
      )
    }
    let original = try plan.withoutListMutation
    let layout = try original.resolve(snapshot: snapshot)
    let base = try prepare(
      SourceFix.Edit(
        source: edit.source,
        replacement: edit.source.text,
        layout: original
      )
    )
    let ordered = try layout.sources.map { try list.index(of: $0.source) }
    let groups = try value.groups(in: list, ordered: ordered)
    let total = groups.reduce(0) { $0 + $1.count }
    let byIndex = Dictionary(uniqueKeysWithValues: zip(ordered, groups))
    let trailingComma =
      list.elements.last
        .flatMap(SourceListEditing.comma) != nil
    let nested = try (original.formatting?.nested ?? [])
      .filter { $0.ownership == .independent }
      .map { try $0.resolve(snapshot: snapshot) }
    let independent = try composeTree(
      edits: layout.edits + nested + children.flatMap(\.flattenedEdits),
      validating: false
    )
    let contained = try (original.formatting?.nested ?? [])
      .filter { $0.ownership == .withLayout }
      .map { try $0.resolve(snapshot: snapshot) }
    let attachments = try composeTree(
      edits: independent.flatMap(\.flattenedEdits) + contained,
      validating: false
    )
    for child in attachments {
      guard try owns(child.edit, plan: plan)
      else { throw SourceError.overlappingEdits }
    }
    var rendered = 0
    func events(
      for provider: any SourceProviding,
      separator: SourceLayoutRenderer.Separator
    ) throws -> [SourceLayoutDocument.Event] {
      let index = try list.index(of: provider.source)
      guard let elements = byIndex[index]
      else { throw SourceError.syntaxMismatch }
      var result: [SourceLayoutDocument.Event] = []
      for element in elements {
        if !result.isEmpty {
          result.append(.boundary(separator == .space ? .soft : .newline))
        }
        rendered += 1
        let punctuation = list.hasCommas && (rendered < total || trailingComma)
          ? "," : ""
        let content: SourceLayoutContent
        switch element {
        case let .inserted(text):
          let source = try SourceSlice(
            snapshot: snapshot,
            range: list.source.range.lowerBound..<list.source.range.lowerBound
          )
          let trimmed = SourceLayoutPrepared.trim(text)
          content = SourceLayoutContent(
            source: source, originalIndentation: "", baseline: trimmed,
            changes: [.init(range: source.range, value: .text(trimmed))]
          )
        case let .original(index):
          let item = items[index]
          content = try prepareContent(
            SourceSlice(snapshot: snapshot, range: item.contentRange),
            applying: [],
            adding: attachments.filter {
              SourceLayoutComposition.contains(
                item.contentRange,
                $0.edit.source.range
              )
            }
          )
        }
        result.append(.element(content, separator: punctuation))
      }
      return result
    }
    let document = try SourceLayoutDocument(
      layout.node, separator: base.context.defaultSeparator,
      sourceEvents: { try events(for: $0, separator: $1) },
      editEvents: { try events(for: $0.source, separator: $1) }
    )
    let baseline = try value.preservingSource(
      in: list,
      session: self,
      children: independent
    )
    return SourceLayoutPrepared(
      source: edit.source, capture: plan,
      content: SourceLayoutContent(
        source: edit.source,
        originalIndentation: base.content.originalIndentation,
        baseline: baseline,
        changes: []
      ),
      lookaheadText: baseline, document: document, context: base.context,
      originalPlacement: base.originalPlacement,
      indentsContents: base.indentsContents, closesOwner: base.closesOwner,
      hasBaseIndentation: base.hasBaseIndentation
    )
  }
}

extension SourceLayoutPlan {
  var withoutListMutation: Self {
    get throws {
      guard case let .listMutation(_, layout?) = mode
      else { throw SourceError.syntaxMismatch }
      return Self(
        elements: elements,
        targetRange: targetRange,
        mode: .layout(layout)
      )
    }
  }
}
