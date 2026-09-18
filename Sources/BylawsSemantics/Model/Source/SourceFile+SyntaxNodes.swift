import SwiftSyntax

extension SourceFile {
  /// Returns the syntax nodes of the requested kinds in source order.
  ///
  /// The query covers every `#if` branch. Each call parses the file again.
  /// - Complexity: O(n), where n is the length of the source file.
  public func syntaxNodes(
    of kind: SourceNode.Kind,
    _ additionalKinds: SourceNode.Kind...
  ) -> [SourceNode] {
    syntaxNodes(of: Set([kind] + additionalKinds))
  }

  package func syntaxNodes(of kinds: Set<SourceNode.Kind>) -> [SourceNode] {
    let source = SourceText(
      source: sourceText,
      swiftLanguageMode: swiftLanguageMode
    )
    let collector = SourceNodeCollector(
      context: SourceContext(source: source, origin: .start(of: path)),
      kinds: kinds
    )
    collector.walk(swiftLanguageMode.parse(sourceText))
    return collector.nodes
  }
}
