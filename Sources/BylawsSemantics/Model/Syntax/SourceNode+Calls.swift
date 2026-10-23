import BylawsSyntax

extension SourceNode {
  /// The call represented by this node, including a macro expansion.
  ///
  /// Recognises calls enclosed by `try`, `await` or parentheses.
  /// Other node forms return `nil`. The call retains its original arguments,
  /// location and source.
  /// - Complexity: O(n), where n is the length of the call text and its
  ///   enclosing expressions.
  public var call: FunctionCall? {
    let reader = SyntaxReader(
      path: context.origin.filePath,
      text: context.source
    )
    var node = syntax
    while true {
      switch node.as(SyntaxEnum.self) {
      case let .functionCallExpr(call):
        return reader.call(call)
      case let .macroExpansionExpr(macro):
        return reader.call(
          named: macro.macroName.text,
          arguments: macro.arguments,
          at: macro
        )
      case let .macroExpansionDecl(macro):
        return reader.call(
          named: macro.macroName.text,
          arguments: macro.arguments,
          at: macro
        )
      case let .tryExpr(expression):
        node = Syntax(expression.expression)
      case let .awaitExpr(expression):
        node = Syntax(expression.expression)
      case let .tupleExpr(tuple):
        guard tuple.elements.count == 1,
              let element = tuple.elements.first,
              element.label == nil,
              element.trailingComma == nil
        else { return nil }
        node = Syntax(element.expression)
      default:
        return nil
      }
    }
  }
}
