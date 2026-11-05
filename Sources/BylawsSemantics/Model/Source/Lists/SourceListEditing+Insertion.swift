import BylawsSyntax

extension SourceListEditing {
  static func insert(
    _ text: String, into list: SourceListSyntax, at position: SourceListPosition
  ) throws -> SourceCorrection {
    let index = try position.offset(count: list.elements.count)
    if let failure = check(list) { return failure }
    guard let element = insertedElement(
      text,
      kind: list.context.kind,
      mode: list.source.snapshot
        .swiftLanguageMode
    ),
      !hasOuterComments(element)
    else {
      return .unavailable(
        "Insert takes one complete list element. Use text that parses as an element of the selected list."
      )
    }
    let content = element.trimmedDescription
    let context = context(for: list)
    let indentation = indentation(in: list, context: context)
    if !indentation.isEmpty,
       element.tokens(viewMode: .sourceAccurate)
         .contains(where: { $0.tokenKind == .multilineStringQuote })
    {
      return .unavailable(
        "Insert must preserve multiline string indentation. Insert the string with an explicit source correction."
      )
    }
    let indented = try SourceLayoutText(
      content,
      originalIndentation: "",
      indentation: indentation
    ).text
    let separator = list.isVertical ? context.lineEnding + indentation : " "
    if list.elements.isEmpty {
      guard list.source.text.allSatisfy(\.isWhitespace)
      else { return .unavailable(commentReason) }
      let replacement: String = switch list.context.kind {
      case .attributes, .modifiers: indented + " "
      case .arguments:
        if list.addsParentheses {
          "(" + indented + ")"
        } else if list.isVertical {
          context.lineEnding + indentation + indented + context.lineEnding
            + context.indentation(before: list.context.owner.range.lowerBound)
        } else { indented }
      case .members, .statements:
        context.lineEnding + indentation + indented + context.lineEnding
          + context.indentation(before: list.context.owner.range.lowerBound)
      }
      return try correction(
        replacing: list.source.range,
        with: replacement,
        in: list
      )
    }
    if index < list.elements.count {
      let next = list.elements[index]
      guard !hasOuterComments(next) else { return .unavailable(commentReason) }
      let offset = next.positionAfterSkippingLeadingTrivia.utf8Offset
      return try correction(
        replacing: offset..<offset,
        with: indented + (list.hasCommas ? "," : "") + separator, in: list
      )
    }
    let last = list.elements[list.elements.count - 1]
    guard !hasOuterComments(last) else { return .unavailable(commentReason) }
    let offset = last.endPositionBeforeTrailingTrivia.utf8Offset
    let keepsTrailingComma = comma(of: last) != nil
    let prefix = list.hasCommas && !keepsTrailingComma ? "," : ""
    let suffix = keepsTrailingComma ? "," : ""
    return try correction(
      replacing: offset..<offset, with: prefix + separator + indented + suffix,
      in: list
    )
  }

  private static func insertedElement(
    _ text: String, kind: SourceListContext.Kind, mode: SwiftLanguageMode
  ) -> Syntax? {
    let source = switch kind {
    case .arguments: "__bylaws__(\(text))"
    case .attributes, .modifiers: "\(text) struct __Bylaws {}"
    case .members: "struct __Bylaws {\(text)}"
    case .statements: "func __bylaws__() {\(text)}"
    }
    let tree = mode.parse(source)
    guard !tree.hasError, tree.statements.count == 1,
          let statement = tree.statements.first
    else { return nil }
    let elements: [Syntax]
    switch kind {
    case .arguments:
      guard let call = statement.item.as(FunctionCallExprSyntax.self)
      else { return nil }
      elements = call.arguments.map(Syntax.init)
    case .attributes, .modifiers, .members:
      guard let declaration = statement.item.as(StructDeclSyntax.self),
            declaration.name.text == "__Bylaws"
      else { return nil }
      elements = switch kind {
      case .attributes: declaration.attributes.map(Syntax.init)
      case .modifiers: declaration.modifiers.map(Syntax.init)
      default: declaration.memberBlock.members.map(Syntax.init)
      }
    case .statements:
      guard let function = statement.item.as(FunctionDeclSyntax.self),
            let body = function.body else { return nil }
      elements = body.statements.map(Syntax.init)
    }
    let trimmed = String(
      text.drop(while: \.isWhitespace).reversed()
        .drop(while: \.isWhitespace).reversed()
    )
    guard elements.count == 1, let element = elements.first,
          element.trimmedDescription.utf8.elementsEqual(trimmed.utf8),
          comma(of: element) == nil,
          element.as(CodeBlockItemSyntax.self)?.semicolon == nil,
          element.as(MemberBlockItemSyntax.self)?.semicolon == nil
    else { return nil }
    return element
  }
}
