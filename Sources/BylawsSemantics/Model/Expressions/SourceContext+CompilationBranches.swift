import BylawsSyntax

extension SourceContext {
  func compilationBranches(of syntax: some SyntaxProtocol)
    -> [CompilationBranch]
  {
    let position = location(at: syntax.positionAfterSkippingLeadingTrivia)
    var result: [CompilationBranch] = []
    var parent = syntax.parent
    while let node = parent {
      if let clause = node.as(IfConfigClauseSyntax.self) {
        let branch = CompilationBranch(clause, context: self)
        if branch.contains(position) { result.append(branch) }
      }
      parent = node.parent
    }
    return inheritedBranches + result.reversed()
  }
}

extension SourceExpression {
  /// The conditional-compilation branches that contain the expression,
  /// starting with the outermost branch.
  ///
  /// For an expression read from a call argument, the list is limited to
  /// branches inside that argument. To include branches around the call,
  /// use the source file's `expressions` property.
  public var compilationBranches: [CompilationBranch] {
    context.compilationBranches(of: syntax)
  }
}
