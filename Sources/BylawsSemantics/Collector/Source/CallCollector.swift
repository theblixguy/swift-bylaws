import SwiftSyntax

final class CallCollector: LexicalRegionVisitor {
  private let reader: SyntaxReader
  private(set) var calls: [FunctionCall] = []

  init(
    path: String,
    text: SourceText,
    visitsTopLevelAccessors: Bool = false
  ) {
    reader = SyntaxReader(path: path, text: text)
    super.init(visitsTopLevelAccessors: visitsTopLevelAccessors)
  }

  override func visit(_ node: FunctionCallExprSyntax)
    -> SyntaxVisitorContinueKind
  {
    calls.append(reader.call(node))
    return .visitChildren
  }

  override func visit(_ node: MacroExpansionExprSyntax)
    -> SyntaxVisitorContinueKind
  {
    calls.append(
      reader.call(
        named: node.macroName.text,
        arguments: node.arguments,
        at: node
      )
    )
    return .visitChildren
  }
}
