public import SwiftSyntax

extension SourceFile {
  /// Runs `body` with a freshly parsed syntax tree for this file.
  public func withSyntax<R>(_ body: (SourceFileSyntax) throws -> R) rethrows
    -> R
  {
    try body(swiftLanguageMode.parse(sourceText))
  }

  /// Runs `body` with the syntax node for `declaration`.
  ///
  /// Returns `nil` when the declaration belongs to another file or no node of
  /// `syntaxType` exists at its position.
  ///
  /// ```swift
  /// file.withSyntax(of: viewModel, as: ClassDeclSyntax.self) { node in
  ///     node.memberBlock.members.count
  /// }
  /// ```
  public func withSyntax<S: SyntaxProtocol, R>(
    of declaration: some Located,
    as syntaxType: S.Type,
    _ body: (S) throws -> R
  ) rethrows -> R? {
    try withSyntaxSession {
      try $0.withSyntax(of: declaration, as: syntaxType, body)
    }
  }

  /// Runs `body` with a session that resolves several declarations from
  /// one parsed syntax tree.
  public func withSyntaxSession<R>(
    _ body: (SourceSyntaxSession) throws -> R
  ) rethrows -> R {
    try body(SourceSyntaxSession(
      path: path, source: sourceText, swiftLanguageMode: swiftLanguageMode
    ))
  }
}

/// A syntax tree used to resolve several declarations from one source file.
public struct SourceSyntaxSession {
  private let path: String
  private let tree: SourceFileSyntax
  private let lines: SourceLineTable

  fileprivate init(
    path: String,
    source: String,
    swiftLanguageMode: SwiftLanguageMode
  ) {
    self.path = path
    tree = swiftLanguageMode.parse(source)
    lines = SourceLineTable(source.utf8)
  }

  /// Runs `body` with the syntax node at `declaration`, or returns `nil`
  /// when the declaration belongs to another file or has no node of the
  /// requested type.
  public func withSyntax<S: SyntaxProtocol, R>(
    of declaration: some Located,
    as syntaxType: S.Type,
    _ body: (S) throws -> R
  ) rethrows -> R? {
    guard declaration.location.filePath == path else { return nil }
    let location = declaration.location
    guard let offset = location.utf8Offset
      ?? lines.offset(line: location.line, column: location.column)
    else { return nil }
    let position = AbsolutePosition(utf8Offset: offset)
    var node: Syntax? = tree.token(at: position).map(Syntax.init)
    while let current = node {
      if let match = current.as(S.self) {
        return try body(match)
      }
      node = current.parent
    }
    return nil
  }
}
