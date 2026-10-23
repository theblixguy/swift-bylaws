/// A lexical token from a captured Swift source file.
public struct SourceToken: SourceProviding, Sendable, Hashable {
  let context: SourceLexicalContext
  let index: Int

  /// The token's lexical category.
  public var kind: Kind { context.tokens[index].kind }

  /// The exact token text, excluding its trivia.
  /// - Complexity: O(n), where n is the source file's UTF-8 length.
  public var text: String { source.text }

  /// The token's original source, excluding its trivia.
  public var source: SourceSlice { context.tokens[index].source }

  /// The preceding token in the original file, including outside the queried slice.
  public var previous: Self? {
    index > 0 ? Self(context: context, index: index - 1) : nil
  }

  /// The following token in the original file, including outside the queried slice.
  public var next: Self? {
    index + 1 < context.tokens.count
      ? Self(context: context, index: index + 1) : nil
  }

  /// The token's original leading whitespace and comments.
  public var leadingTrivia: [SourceTrivia] {
    context.tokens[index].leadingTrivia
  }

  /// The token's original trailing whitespace and comments.
  public var trailingTrivia: [SourceTrivia] {
    context.tokens[index].trailingTrivia
  }

  /// Compares tokens by their category and captured source.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.kind == rhs.kind && lhs.source == rhs.source
  }

  /// Hashes the token's category and captured source.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(kind)
    hasher.combine(source)
  }
}
