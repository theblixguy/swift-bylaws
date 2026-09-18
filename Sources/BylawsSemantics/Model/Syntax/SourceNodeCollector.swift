import BylawsSyntax

final class SourceNodeCollector: SyntaxAnyVisitor {
  private let context: SourceContext
  private let kinds: Set<SourceNode.Kind>
  private(set) var nodes: [SourceNode] = []

  init(context: SourceContext, kinds: Set<SourceNode.Kind>) {
    self.context = context
    self.kinds = kinds
    super.init(viewMode: .sourceAccurate)
  }

  override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
    if let kind = SourceNode.Kind(node), kinds.contains(kind) {
      nodes.append(SourceNode(node, context: context, kind: kind))
    }
    return .visitChildren
  }
}
