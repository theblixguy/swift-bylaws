import BylawsSyntax

extension SourceListMutationPlan.Mutation {
  enum Element {
    case original(Int)
    case inserted(String)
  }

  func groups(
    in list: SourceListSyntax, ordered indices: [Int]
  ) throws -> [[Element]] {
    var removed: Set<Int> = []
    var insertions: [Int: [String]] = [:]
    var start: [String] = []
    var end: [String] = []
    var seen: Set<SourceListMutationPlan.Operation> = []
    for operation in operations {
      guard seen.insert(operation).inserted else { continue }
      switch operation {
      case let .remove(range):
        let source = try SourceSlice(
          snapshot: list.source.snapshot,
          range: range
        )
        removed.insert(try list.index(of: source))
      case let .insert(text, position):
        switch position {
        case .start: start.append(text)
        case .end: end.append(text)
        case let .index(index):
          _ = try position.offset(count: list.elements.count)
          if index == list.elements.count { end.append(text) }
          else { insertions[index, default: []].append(text) }
        }
      }
    }
    guard !indices.isEmpty else {
      return [(start + end).map(Element.inserted)]
    }
    return indices.enumerated().map { offset, index in
      var values = (insertions[index] ?? []).map(Element.inserted)
      if !removed.contains(index) { values.append(.original(index)) }
      if offset == 0 { values.insert(
        contentsOf: start.map(Element.inserted),
        at: 0
      ) }
      if offset == indices.count - 1 {
        values.append(contentsOf: end.map(Element.inserted))
      }
      return values
    }
  }

  func preservingSource(
    in list: SourceListSyntax,
    context suppliedContext: SourceLayoutReplacement.Context? = nil,
    session: SourceLayoutComposition.Session,
    children: [SourceLayoutComposition.Session.ComposedEdit]
  ) throws -> String {
    if operations.count == 1, children.isEmpty {
      let raw = try edits(snapshot: list.source.snapshot)
      return try list.source.replacement(applying: raw).replacement
    }
    let elements = try groups(in: list, ordered: Array(list.elements.indices))
      .flatMap(\.self)
    let context = suppliedContext ?? SourceListEditing.context(for: list)
    let ownerIndent =
      context.indentation(before: list.context.owner.range.lowerBound)
    let indent = SourceListEditing.indentation(in: list, context: context)
    let separator = list.isVertical ? context.lineEnding + indent : " "
    if elements.isEmpty {
      return switch list.context.kind {
      case .attributes,
           .modifiers: String(list.source.text.prefix(while: \.isWhitespace))
      case .members,
           .statements: list.isVertical ? context.lineEnding + ownerIndent : ""
      case .arguments: ""
      }
    }
    var output = ""
    if list.elements.isEmpty {
      if list.addsParentheses { output = "(" }
      else if list.isVertical { output = context.lineEnding + indent }
    } else {
      let first = list.elements[0]
      output = try SourceListEditing.text(
        list.source.range.lowerBound..<first.positionAfterSkippingLeadingTrivia
          .utf8Offset,
        in: list
      )
    }
    let trailingComma = list.elements.last
      .flatMap(SourceListEditing.comma) != nil
    for (offset, element) in elements.enumerated() {
      if offset > 0 {
        if case let .original(previous) = elements[offset - 1],
           previous + 1 < list.elements.count
        {
          output += try SourceListEditing.text(
            list.elements[previous].endPositionBeforeTrailingTrivia.utf8Offset
              ..< list.elements[previous + 1].positionAfterSkippingLeadingTrivia
              .utf8Offset,
            in: list
          )
        } else { output += separator }
      }
      switch element {
      case let .inserted(text):
        output += try SourceLayoutText(
          SourceLayoutPrepared.trim(text), originalIndentation: "",
          indentation: indent
        ).text
      case let .original(index):
        let node = list.elements[index]
        let range = node.positionAfterSkippingLeadingTrivia.utf8Offset
          ..< SourceLayoutReplacement.Item.contentEnd(of: node)
        let source = try SourceSlice(
          snapshot: list.source.snapshot,
          range: range
        )
        let nested = children.filter { SourceLayoutComposition.contains(
          range,
          $0.edit.source.range
        ) }
        output += try session.content(
          source, applying: [], adding: nested,
          at: .init(column: 0, indentation: indent, lineIndentation: indent)
        )
      }
      if list.hasCommas,
         offset + 1 < elements.count || trailingComma { output += "," }
    }
    if list.addsParentheses { output += ")" }
    else if let last = list.elements.last {
      output += try SourceListEditing.text(
        last.endPositionBeforeTrailingTrivia.utf8Offset..<list.source.range
          .upperBound,
        in: list
      )
    } else if list.isVertical { output += context.lineEnding + ownerIndent }
    else if list.context.kind == .attributes
      || list.context.kind == .modifiers
    {
      output += " "
    }
    return output
  }
}
