import BylawsSyntax

enum SourceListEditing {
  static let commentReason =
    "SourceList must preserve comments at the edit boundary. Select an element with separate comments."

  static func check(_ list: SourceListSyntax) -> SourceCorrection? {
    if list.source.snapshot.syntaxTree().hasError {
      return .undetermined(
        "SourceList cannot read a file with syntax errors. Correct the source and run the rule again."
      )
    }
    if list.syntax.tokens(viewMode: .sourceAccurate).contains(where: { token in
      token.tokenKind == .poundIf || token.tokenKind == .poundSourceLocation
        || token.leadingTrivia.contains(where: \.isLayoutControl)
        || token.trailingTrivia.contains(where: \.isLayoutControl)
    }) {
      return .unavailable(
        "SourceList must preserve conditional compilation and formatting directives. Select a list without these boundaries."
      )
    }
    return nil
  }

  static func text(
    _ range: Range<Int>,
    in list: SourceListSyntax
  ) throws -> String {
    try SourceSlice(snapshot: list.source.snapshot, range: range).text
  }

  static func isWhitespace(
    _ range: Range<Int>,
    in list: SourceListSyntax
  ) throws -> Bool {
    try text(range, in: list).allSatisfy(\.isWhitespace)
  }

  static func correction(
    replacing range: Range<Int>, with text: String, in list: SourceListSyntax
  ) throws -> SourceCorrection {
    let source = try SourceSlice(snapshot: list.source.snapshot, range: range)
    return SourceCorrection(edits: [source.replacement(with: text)])
  }

  static func context(for list: SourceListSyntax) -> SourceLayoutReplacement
    .Context
  {
    SourceLayoutReplacement.Context(
      snapshot: list.source.snapshot,
      bytes: list.source.snapshot.syntaxContext?
        .bytes ?? Array(list.source.snapshot.text.utf8),
      excluding: list.source.range
    )
  }

  static func comma(of node: Syntax) -> TokenSyntax? {
    node.as(LabeledExprSyntax.self)?.trailingComma
  }

  static func indentation(
    in list: SourceListSyntax, context: SourceLayoutReplacement.Context
  ) -> String {
    if list.elements.isEmpty {
      return context.indentation(before: list.context.owner.range.lowerBound)
        + (list.isVertical ? context.indentationUnit : "")
    }
    let values = list.elements.map {
      context
        .indentation(before: $0.positionAfterSkippingLeadingTrivia.utf8Offset)
    }
    return values.first(where: { !$0.isEmpty }) ?? ""
  }

  static func hasOuterComments(_ node: Syntax) -> Bool {
    if !node.leadingTrivia.allSatisfy(\.isLayoutWhitespace)
      || !node.trailingTrivia.allSatisfy(\.isLayoutWhitespace)
    {
      return true
    }
    guard let argument = node.as(LabeledExprSyntax.self) else { return false }
    return !argument.expression.leadingTrivia.allSatisfy(\.isLayoutWhitespace)
      || !argument.expression.trailingTrivia.allSatisfy(\.isLayoutWhitespace)
      || [argument.label, argument.colon, argument.trailingComma]
      .compactMap(\.self)
      .contains {
        !$0.leadingTrivia.allSatisfy(\.isLayoutWhitespace)
          || !$0.trailingTrivia.allSatisfy(\.isLayoutWhitespace)
      }
  }
}
