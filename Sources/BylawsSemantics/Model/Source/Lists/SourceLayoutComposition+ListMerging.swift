import BylawsSyntax

extension SourceLayoutComposition.Session {
  private struct ListKey: Hashable {
    let owner: Range<Int>
    let kind: SourceListContext.Kind
  }

  func mergingListMutations(_ edits: [SourceFix.Edit]) throws
    -> [SourceFix.Edit]
  {
    guard edits.contains(where: { $0.layout?.listMutation != nil })
    else { return edits }
    var operations: [ListKey: [SourceListMutationPlan.Operation]] = [:]
    var layouts: [ListKey: SourceLayoutPlan] = [:]
    var order: [ListKey] = []
    for edit in edits {
      guard let plan = edit.layout,
            let mutation = plan.listMutation else { continue }
      guard edit.source.snapshot == snapshot
      else { throw SourceError.differentSnapshots }
      for value in mutation.mutations {
        let key = ListKey(owner: value.owner, kind: value.kind)
        if operations[key] == nil { order.append(key) }
        operations[key, default: []] += value.operations
        if let formatting = plan.formatting {
          layouts[key] = SourceLayoutPlan(
            elements: plan.elements, targetRange: plan.targetRange,
            mode: .layout(formatting)
          )
        }
      }
    }
    let lists = try Dictionary(uniqueKeysWithValues: order.map { key in
      (
        key,
        try SourceListContext(owner: SourceSlice(
          snapshot: snapshot,
          range: key.owner
        ), kind: key.kind).resolve()
      )
    })
    let otherEdits = try separateListLayouts(
      edits, lists: lists, layouts: &layouts
    )
    let pending = try order.map { key in
      guard let list = lists[key],
            let values = operations[key]
      else { throw SourceError.syntaxMismatch }
      let mutation = SourceListMutationPlan(
        mutations: [.init(
          owner: key.owner,
          kind: key.kind,
          operations: values
        )],
        formatsElements: layouts[key] != nil
      )
      let layout = layouts[key]
      let elements = try layout?.elements ?? list.slices().map(\.range)
      return try listMutationEdit(
        source: list.source, elements: elements, formatting: layout?.formatting,
        mutation: mutation
      )
    }
    return try otherEdits + mergingDeclarationPrefixes(pending)
  }

  private func separateListLayouts(
    _ edits: [SourceFix.Edit], lists: [ListKey: SourceListSyntax],
    layouts: inout [ListKey: SourceLayoutPlan]
  ) throws -> [SourceFix.Edit] {
    let keysByList = Dictionary(uniqueKeysWithValues: lists.map { (
      $0.value.syntax.id,
      $0.key
    ) })
    var otherEdits: [SourceFix.Edit] = []
    for edit in edits where edit.layout?.listMutation == nil {
      guard let plan = edit.layout, let formatting = plan.formatting,
            let first = plan.elements.first
      else { otherEdits.append(edit)
        continue
      }
      let item = try SourceLayoutReplacement.Item(
        source: SourceSlice(snapshot: snapshot, range: first), tree: tree,
        validatesTrailingTrivia: false
      )
      guard let identity = item.node.parent?.id, let key = keysByList[identity],
            let list = lists[key], plan.elements.count == list.elements.count
      else { otherEdits.append(edit)
        continue
      }
      let expanded = SourceLayoutPlan(
        elements: plan.elements, targetRange: list.source.range,
        mode: .layout(.init(
          node: formatting.node, baseIndentation: formatting.baseIndentation,
          condition: formatting.condition, nested: formatting.nested
        ))
      )
      guard layouts[key] == nil || layouts[key] == expanded
      else { throw SourceError.overlappingEdits }
      layouts[key] = expanded
    }
    return otherEdits
  }

  private func mergingDeclarationPrefixes(_ edits: [SourceFix.Edit]) throws
    -> [SourceFix.Edit]
  {
    var result: [SourceFix.Edit] = []
    var prefixes: [Range<Int>: SourceFix.Edit] = [:]
    for edit in edits {
      guard let mutation = edit.layout?.listMutation,
            !mutation.formatsElements, let value = mutation.mutations.first,
            value.kind == .attributes || value.kind == .modifiers
      else { result.append(edit)
        continue
      }
      guard let previous = prefixes.removeValue(forKey: value.owner),
            let other = previous.layout?.listMutation
      else { prefixes[value.owner] = edit
        continue
      }
      let source = try SourceSlice(
        snapshot: snapshot,
        range: min(
          previous.source.range.lowerBound,
          edit.source.range.lowerBound
        )
          ..< max(
            previous.source.range.upperBound,
            edit.source.range.upperBound
          )
      )
      let elements = (previous.layout?.elements ?? []) +
        (edit.layout?.elements ?? [])
      result.append(try listMutationEdit(
        source: source, elements: elements, formatting: nil,
        mutation: .init(
          mutations: other.mutations + mutation.mutations,
          formatsElements: false
        )
      ))
    }
    result.append(contentsOf: prefixes.values)
    return result
  }

  private func listMutationEdit(
    source: SourceSlice, elements: [Range<Int>],
    formatting: SourceLayoutPlan.Layout?,
    mutation: SourceListMutationPlan
  ) throws -> SourceFix.Edit {
    let plan = SourceLayoutPlan(
      elements: elements, targetRange: source.range,
      mode: .listMutation(mutation, layout: formatting)
    )
    let edit = SourceFix.Edit(
      source: source,
      replacement: source.text,
      layout: plan
    )
    return SourceFix.Edit(
      source: source,
      replacement: try render(edit),
      layout: plan
    )
  }
}
