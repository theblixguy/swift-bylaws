extension SourceLayoutComposition {
  package static func attaching(
    _ children: [SourceFix.Edit], to parents: [SourceFix.Edit]
  ) throws -> [SourceFix.Edit] {
    guard let first = parents.first else { return [] }
    let session = Session(snapshot: first.source.snapshot)
    var contained = Array(repeating: [SourceFix.Edit](), count: parents.count)
    for child in children {
      guard child.source.snapshot == session.snapshot else {
        throw SourceError.differentSnapshots
      }
      try session.validate(child)
      guard let index = try parents.indices.first(where: { index in
        guard let plan = parents[index].layout,
              plan.formatting != nil else { return false }
        return try session.owns(child, plan: plan)
      }) else { throw SourceError.overlappingEdits }
      contained[index].append(child)
    }
    return try parents.enumerated().map { index, parent in
      guard parent.source.snapshot == session.snapshot else {
        throw SourceError.differentSnapshots
      }
      try session.validate(parent)
      guard !contained[index].isEmpty else { return parent }
      guard let plan = parent.layout, let formatting = plan.formatting else {
        throw SourceError.syntaxMismatch
      }
      let attached = SourceLayoutPlan.Layout(
        node: formatting.node, allowsPartialList: formatting.allowsPartialList,
        baseIndentation: formatting.baseIndentation,
        trimmed: formatting.trimmed,
        condition: formatting.condition,
        nested: formatting.nested + contained[index].map { .init(
          $0,
          ownership: .withLayout
        ) }
      )
      let mode: SourceLayoutPlan.Mode = if let mutation = plan.listMutation {
        .listMutation(mutation, layout: attached)
      } else { .layout(attached) }
      let updated = SourceLayoutPlan(
        elements: plan.elements,
        targetRange: plan.targetRange,
        mode: mode
      )
      let proposed = SourceFix.Edit(
        source: parent.source,
        replacement: parent.source.text,
        layout: updated
      )
      return try SourceFix.Edit(
        source: parent.source,
        replacement: session.render(proposed),
        layout: updated
      )
    }
  }
}
