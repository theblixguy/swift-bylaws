import BylawsSyntax

/// One captured piece of whitespace, a comment or other text between tokens.
public struct SourceTrivia: SourceProviding, Sendable, Hashable {
  /// The trivia's lexical category.
  public let kind: Kind

  /// The trivia's original source.
  public let source: SourceSlice

  /// The exact trivia text, including comment delimiters.
  /// - Complexity: O(n), where n is the source file's UTF-8 length.
  public var text: String { source.text }

  /// Whether the trivia is a line, block or documentation comment.
  public var isComment: Bool {
    switch kind {
    case .lineComment, .blockComment, .docLineComment, .docBlockComment: true
    default: false
    }
  }

  /// The lexical category of a captured trivia piece.
  public enum Kind: String, CaseIterable, Sendable, Hashable, Codable {
    /// Escaped line endings in a multiline string.
    case backslashes
    /// A block comment, including its delimiters.
    case blockComment
    /// Carriage return characters.
    case carriageReturns
    /// Carriage return and line feed pairs.
    case carriageReturnLineFeeds
    /// A documentation block comment, including its delimiters.
    case docBlockComment
    /// A documentation line comment, excluding the line ending.
    case docLineComment
    /// Form feed characters.
    case formfeeds
    /// A line comment, excluding the line ending.
    case lineComment
    /// Line feed characters.
    case newlines
    /// Pound characters in a multiline string's escaped line ending.
    case pounds
    /// Space characters.
    case spaces
    /// Tab characters.
    case tabs
    /// Text skipped by the parser.
    case unexpectedText
    /// Vertical tab characters.
    case verticalTabs

    init(_ trivia: TriviaPiece) {
      switch trivia {
      case .backslashes: self = .backslashes
      case .blockComment: self = .blockComment
      case .carriageReturns: self = .carriageReturns
      case .carriageReturnLineFeeds: self = .carriageReturnLineFeeds
      case .docBlockComment: self = .docBlockComment
      case .docLineComment: self = .docLineComment
      case .formfeeds: self = .formfeeds
      case .lineComment: self = .lineComment
      case .newlines: self = .newlines
      case .pounds: self = .pounds
      case .spaces: self = .spaces
      case .tabs: self = .tabs
      case .unexpectedText: self = .unexpectedText
      case .verticalTabs: self = .verticalTabs
      @unknown default: self = .unexpectedText
      }
    }
  }
}
