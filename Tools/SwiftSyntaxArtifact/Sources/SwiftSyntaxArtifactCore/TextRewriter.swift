import RegexBuilder

package struct TextRewriter: Sendable {
  package func replacingModuleReferences(
    in source: String,
    from original: String,
    to replacement: String
  ) -> String {
    source
      .replacing(importPattern(original), with: "import \(replacement)")
      .replacing(
        canImportPattern(original),
        with: "canImport(\(replacement)"
      )
      .replacing(qualifiedNamePattern(original), with: "\(replacement).")
  }

  package func containsModuleReference(
    _ module: String,
    in source: String
  ) -> Bool {
    source.contains(importPattern(module))
      || source.contains(canImportPattern(module))
      || source.contains(qualifiedNamePattern(module))
  }

  package func replacingCSymbols(
    in source: String,
    with prefix: String
  ) -> String {
    source.replacing(cSymbolPattern) {
      "\(prefix)\($0.1)"
    }
  }

  package func containsCSymbol(in source: String) -> Bool {
    source.contains(cSymbolPattern)
  }

  package func replacingCModuleName(
    in source: String,
    with replacement: String
  ) -> String {
    source.replacing(cModuleNamePattern, with: replacement)
  }

  package func containsCModuleName(in source: String) -> Bool {
    source.contains(cModuleNamePattern)
  }

  private var cModuleNamePattern: Regex<Substring> {
    Regex {
      Anchor.wordBoundary
      "_SwiftSyntaxCShims"
      Anchor.wordBoundary
    }
  }

  private func importPattern(_ module: String) -> Regex<Substring> {
    Regex {
      Anchor.wordBoundary
      "import"
      OneOrMore(.horizontalWhitespace)
      module
      Anchor.wordBoundary
    }
  }

  private func canImportPattern(_ module: String) -> Regex<Substring> {
    Regex {
      Anchor.wordBoundary
      "canImport("
      ZeroOrMore(.horizontalWhitespace)
      module
      Anchor.wordBoundary
    }
  }

  private func qualifiedNamePattern(_ module: String) -> Regex<Substring> {
    Regex {
      Anchor.wordBoundary
      module
      "."
    }
  }

  private var cSymbolPattern: Regex<(Substring, Substring)> {
    Regex {
      Anchor.wordBoundary
      "swiftsyntax_"
      Capture {
        OneOrMore(.word)
      }
      Anchor.wordBoundary
    }
  }
}
