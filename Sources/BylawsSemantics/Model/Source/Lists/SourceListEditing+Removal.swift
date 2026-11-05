import BylawsSyntax

extension SourceListEditing {
  static func remove(_ source: SourceSlice) throws -> SourceCorrection {
    let item: SourceLayoutReplacement.Item
    do {
      item = try SourceLayoutReplacement.Item(
        source: source, tree: source.snapshot.syntaxTree(),
        validatesTrailingTrivia: false
      )
    } catch SourceLayoutReplacementError.unsupportedElement {
      return .unavailable(
        "Remove takes a complete supported list element. Select an argument, attribute, modifier, member or statement."
      )
    }
    guard let parent = item.node.parent, let owner = parent.parent else {
      throw SourceError.syntaxMismatch
    }
    let kind: SourceListContext.Kind
    let ownerNode: Syntax
    switch parent.kind {
    case .labeledExprList:
      kind = .arguments
      ownerNode = owner
    case .attributeList:
      kind = .attributes
      ownerNode = owner
    case .declModifierList:
      kind = .modifiers
      ownerNode = owner
    case .memberBlockItemList:
      kind = .members
      guard let declaration = owner.parent
      else { throw SourceError.syntaxMismatch }
      ownerNode = declaration
    case .codeBlockItemList:
      kind = .statements
      ownerNode = owner
    default:
      return .unavailable(
        "Remove takes a supported list element. Select an argument, attribute, modifier, member or statement."
      )
    }
    let ownerSource = try SourceSlice(
      snapshot: source.snapshot,
      range: ownerNode.positionAfterSkippingLeadingTrivia.utf8Offset
        ..< ownerNode.endPositionBeforeTrailingTrivia.utf8Offset
    )
    let context = SourceListContext(owner: ownerSource, kind: kind)
    do {
      let list = try context.resolve()
      let correction = try remove(source, from: list)
      return try SourceListMutationPlan.capture(
        correction, list: list, operation: .remove(source.range)
      )
    } catch SourceError.missingPart {
      return .unavailable(
        "Remove takes a supported list element. Select an argument, attribute, modifier, member or statement."
      )
    }
  }

  static func remove(
    _ source: SourceSlice,
    from list: SourceListSyntax
  ) throws -> SourceCorrection {
    let index = try list.index(of: source)
    if let failure = check(list) { return failure }
    let element = list.elements[index]
    guard !hasOuterComments(element) else { return .unavailable(commentReason) }
    let start = element.positionAfterSkippingLeadingTrivia.utf8Offset
    let end = element.endPositionBeforeTrailingTrivia.utf8Offset
    if list.elements.count == 1 {
      guard try isWhitespace(list.source.range.lowerBound..<start, in: list),
            try isWhitespace(end..<list.source.range.upperBound, in: list)
      else { return .unavailable(commentReason) }
      let replacement = switch list.context.kind {
      case .attributes, .modifiers:
        String(list.source.text.prefix(while: \.isWhitespace))
      case .members, .statements:
        if list.source.text.contains(where: \.isNewline) {
          list.source.snapshot.lineEnding
            + context(for: list)
            .indentation(before: list.context.owner.range.lowerBound)
        } else { "" }
      default: ""
      }
      return try correction(
        replacing: list.source.range,
        with: replacement,
        in: list
      )
    }
    if index + 1 < list.elements.count {
      let next = list.elements[index + 1]
      let nextStart = next.positionAfterSkippingLeadingTrivia.utf8Offset
      guard try isWhitespace(end..<nextStart, in: list)
      else { return .unavailable(commentReason) }
      return try correction(replacing: start..<nextStart, with: "", in: list)
    }
    let previous = list.elements[index - 1]
    let previousEnd = previous.endPositionBeforeTrailingTrivia.utf8Offset
    guard try isWhitespace(previousEnd..<start, in: list)
    else { return .unavailable(commentReason) }
    let removalStart = if list.hasCommas, comma(of: element) == nil {
      comma(of: previous)?.positionAfterSkippingLeadingTrivia
        .utf8Offset ?? previousEnd
    } else { previousEnd }
    return try correction(replacing: removalStart..<end, with: "", in: list)
  }
}
