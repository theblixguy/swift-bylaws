import Bylaws
import Testing

nonisolated let syntaxCodebase = Codebase(
  root: .automatic(),
  including: ["Tests/InterpreterTests/Support/PortableSyntaxSubject.swift"],
  swiftLanguageMode: .v6
)

nonisolated let manualUnlock = Matcher<SourceNode>(
  "call unlock from defer"
) { node in
  node.kind == SourceNode.Kind.functionCall
    && node.call?.references("lock.unlock") == true
    && node.ancestors.contains { $0.kind == .deferStatement }
}

nonisolated let portableSyntaxRules: [Rule] = [
  Rule("manual-unlock", "Manual unlock calls banned") {
    try await syntaxCodebase.syntaxNodes(
      of: .functionCall,
      .deferStatement
    )
    .under("Tests/InterpreterTests/Support")
    .violations(matching: manualUnlock)
  },
]
