/// Captured syntax to retain in a replacement.
public struct SourceReplacement: Sendable {
  indirect enum Content: Sendable {
    case source(any SourceProviding)
    case sequence([Content])
    case scope(Content)
  }

  let content: Content

  /// Retains one captured syntax node.
  public init(source: some SourceProviding) {
    content = .source(source)
  }

  /// Retains captured syntax nodes in their written order.
  public init<S: Sequence>(sources: S) where S.Element: SourceProviding {
    content = .sequence(sources.map { .source($0) })
  }

  /// Combines retained contents in their written order.
  public init(combining replacements: some Sequence<SourceReplacement>) {
    content = .sequence(replacements.map(\.content))
  }

  /// Describes retained syntax and explicit scopes.
  public init(@SourceReplacementBuilder _ content: () throws -> Self) rethrows {
    self = try content()
  }

  init(content: Content) { self.content = content }
}

/// Builds a replacement from captured syntax and explicit scopes.
@resultBuilder
public enum SourceReplacementBuilder {
  /// Retains one captured syntax node.
  public static func buildExpression(_ source: some SourceProviding)
    -> SourceReplacement
  {
    SourceReplacement(content: .source(source))
  }

  /// Retains captured syntax nodes in their written order.
  public static func buildExpression<S: Sequence>(_ sources: S)
    -> SourceReplacement where S.Element: SourceProviding
  {
    SourceReplacement(content: .sequence(sources.map { .source($0) }))
  }

  /// Retains the captured elements of a source list.
  public static func buildExpression(_ sources: SourceList<some Any>)
    -> SourceReplacement
  {
    SourceReplacement(sources: sources)
  }

  /// Includes an existing replacement description.
  public static func buildExpression(_ replacement: SourceReplacement)
    -> SourceReplacement { replacement }

  /// Includes a scope around retained statements.
  public static func buildExpression(_ scope: Scope) -> SourceReplacement {
    scope.replacement
  }

  /// Combines replacement contents in their written order.
  public static func buildBlock(_ components: SourceReplacement...)
    -> SourceReplacement
  {
    SourceReplacement(content: .sequence(components.map(\.content)))
  }

  /// Includes optional replacement contents.
  public static func buildOptional(_ component: SourceReplacement?)
    -> SourceReplacement
  {
    component ?? SourceReplacement(content: .sequence([]))
  }

  /// Includes the selected conditional contents.
  public static func buildEither(first component: SourceReplacement)
    -> SourceReplacement { component }

  /// Includes the selected conditional contents.
  public static func buildEither(second component: SourceReplacement)
    -> SourceReplacement { component }

  /// Combines contents produced by a loop.
  public static func buildArray(_ components: [SourceReplacement])
    -> SourceReplacement
  {
    SourceReplacement(content: .sequence(components.map(\.content)))
  }

  /// Includes contents for an available API.
  public static func buildLimitedAvailability(_ component: SourceReplacement)
    -> SourceReplacement { component }
}

/// A do block that keeps retained statements in their own scope.
public struct Scope: Sendable {
  /// The retained statements enclosed in a do block.
  public let replacement: SourceReplacement

  /// Places retained statements inside a do block.
  public init(replacement: SourceReplacement) {
    self.replacement = SourceReplacement(content: .scope(replacement.content))
  }

  /// Places the retained statements inside a do block.
  public init(@SourceReplacementBuilder _ content: () throws
    -> SourceReplacement) rethrows
  {
    try self.init(replacement: content())
  }
}
