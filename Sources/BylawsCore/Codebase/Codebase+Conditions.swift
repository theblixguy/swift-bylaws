public import BylawsSemantics

extension Codebase {
  /// The if expressions and statements in the selected files.
  ///
  /// The selection includes every conditional-compilation branch.
  public var ifExpressions: Selection<SourceIfExpression> {
    get async throws(CodebaseError) {
      let nodes = try await syntaxNodes(of: .ifExpression)
      return Selection(
        elements: nodes.compactMap(\.ifExpression),
        queryDescription: nodes.queryDescription, rootPath: nodes.rootPath,
        codebase: self
      )
    }
  }
}
