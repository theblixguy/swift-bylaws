import BylawsSyntax

extension SourceFile {
  /// The conditional-compilation branches in source order, including nested
  /// branches.
  ///
  /// Use ``CompilationBranch/contains(_:)`` to find the branches around a
  /// declaration. Each access parses the file, so save the array in a local
  /// variable when checking several declarations.
  public var compilationBranches: [CompilationBranch] {
    let context = SourceContext(
      source: SourceText(
        source: sourceText,
        swiftLanguageMode: swiftLanguageMode
      ),
      origin: .start(of: path)
    )
    let collector = CompilationBranchCollector(context: context)
    collector.walk(swiftLanguageMode.parse(sourceText))
    return collector.branches
  }
}

private final class CompilationBranchCollector: SyntaxVisitor {
  private let context: SourceContext
  private(set) var branches: [CompilationBranch] = []

  init(context: SourceContext) {
    self.context = context
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: IfConfigClauseSyntax)
    -> SyntaxVisitorContinueKind
  {
    branches.append(CompilationBranch(node, context: context))
    return .visitChildren
  }
}
