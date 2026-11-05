extension SourceLayoutComposition.Session {
  func prepareReplacement(
    _ edit: SourceFix.Edit, plan: SourceLayoutPlan,
    replacement: SourceReplacementPlan, children: [ComposedEdit]
  ) throws -> SourceLayoutPrepared {
    let source = edit.source
    let sourceContext = SourceLayoutReplacement.Context(
      snapshot: snapshot, bytes: bytes, excluding: source.range
    )
    let indentation = sourceContext.indentation(before: source.range.lowerBound)
    let context = SourceLayoutRenderer.Context(
      initialColumn: sourceContext.column(before: source.range.lowerBound),
      initialIndentation: indentation, baseIndentation: indentation,
      indentationUnit: sourceContext.indentationUnit,
      lineEnding: sourceContext.lineEnding
    )
    var document = try replacementDocument(replacement.node, children: children)
    var text = try SourceLayoutRenderer.render(document, context: context)
    if try replacement.needsParentheses(
      afterReplacingWith: text,
      target: source
    ) {
      document = SourceLayoutDocument(events: [.text("(")] + document
        .events + [.text(")")])
      text = try SourceLayoutRenderer.render(document, context: context)
    }
    return SourceLayoutPrepared(
      source: source, capture: plan,
      content: SourceLayoutContent(
        source: source, originalIndentation: indentation,
        baseline: text, changes: []
      ),
      lookaheadText: text, document: document, context: context,
      originalPlacement: .init(
        column: context.initialColumn, indentation: indentation,
        lineIndentation: indentation
      ),
      indentsContents: false, closesOwner: false, hasBaseIndentation: false
    )
  }

  private func replacementDocument(
    _ node: SourceReplacementPlan.Node, children: [ComposedEdit]
  ) throws -> SourceLayoutDocument {
    switch node {
    case let .source(range):
      let retained = try SourceSlice(snapshot: snapshot, range: range)
      let content = try prepareContent(
        retained,
        applying: [],
        adding: children.filter {
          SourceLayoutComposition.contains(range, $0.edit.source.range)
        }
      )
      return SourceLayoutDocument(events: [.content(content)])
    case let .sequence(nodes):
      var events: [SourceLayoutDocument.Event] = []
      for node in nodes {
        let document = try replacementDocument(node, children: children)
        if !events.isEmpty, !document.events.isEmpty {
          events.append(.boundary(.newline))
        }
        events.append(contentsOf: document.events)
      }
      return SourceLayoutDocument(events: events)
    case let .scope(content):
      let document = try replacementDocument(content, children: children)
      return SourceLayoutDocument(events:
        [.text("do {"), .boundary(.newline), .indent]
          + document.events
          + [.endIndentation, .boundary(.newline), .text("}")]
      )
    case let .parentheses(content):
      let document = try replacementDocument(content, children: children)
      return SourceLayoutDocument(events:
        [.text("(")] + document.events + [.text(")")]
      )
    }
  }
}
