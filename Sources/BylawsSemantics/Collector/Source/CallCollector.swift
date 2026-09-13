import SwiftSyntax

final class CallCollector: LexicalRegionVisitor {
  private let path: String
  private let text: SourceText
  private(set) var calls: [FunctionCall] = []

  init(
    path: String,
    text: SourceText,
    visitsTopLevelAccessors: Bool = false
  ) {
    self.path = path
    self.text = text
    super.init(visitsTopLevelAccessors: visitsTopLevelAccessors)
  }

  override func visit(_ node: FunctionCallExprSyntax)
    -> SyntaxVisitorContinueKind
  {
    let start = node.calledExpression.positionAfterSkippingLeadingTrivia
    let position = text.location(of: start)
    calls.append(
      FunctionCall(
        calledExpression: text.trimmedText(of: node.calledExpression),
        arguments: node.arguments.map {
          FunctionCall.Argument(
            label: $0.label?.text,
            text: text.trimmedText(of: $0.expression)
          )
        },
        location: DeclarationLocation(
          filePath: path,
          line: position.line,
          column: position.column,
          utf8Offset: start.utf8Offset
        )
      )
    )
    return .visitChildren
  }

  override func visit(_ node: MacroExpansionExprSyntax)
    -> SyntaxVisitorContinueKind
  {
    let start = node.positionAfterSkippingLeadingTrivia
    let position = text.location(of: start)
    calls.append(
      FunctionCall(
        calledExpression: "#\(node.macroName.text)",
        arguments: node.arguments.map {
          FunctionCall.Argument(
            label: $0.label?.text,
            text: text.trimmedText(of: $0.expression)
          )
        },
        location: DeclarationLocation(
          filePath: path,
          line: position.line,
          column: position.column,
          utf8Offset: start.utf8Offset
        )
      )
    )
    return .visitChildren
  }
}
