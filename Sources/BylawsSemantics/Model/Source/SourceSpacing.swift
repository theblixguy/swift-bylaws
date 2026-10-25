import BylawsSyntax

/// The whitespace immediately before and after a source element.
public struct SourceSpacing: Sendable {
  /// The whitespace before the element and its attached comments.
  public let before: SourceSlice

  /// The whitespace after the element, starting after its last token.
  public let after: SourceSlice

  fileprivate init(around provider: any SourceProviding) throws {
    var source = try provider.source
    let usesDeclarationSource =
      if let node = provider as? SourceNode {
        node.syntax.is(DeclSyntax.self)
      } else {
        provider is any Attributed
      }
    if usesDeclarationSource || provider is FunctionCall.Argument
      || provider is SourceExpression.Argument
    {
      let tree = source.snapshot.swiftLanguageMode.parse(source.snapshot.text)
      do {
        let item = try SourceLayoutReplacement.Item(
          source: source, tree: tree, validatesTrailingTrivia: false
        )
        source = try SourceSlice(
          snapshot: source.snapshot,
          range: item.contentRange
            .lowerBound..<item.node
            .endPositionBeforeTrailingTrivia.utf8Offset
        )
      } catch SourceLayoutReplacementError.unsupportedElement
        where provider is SourceNode
      {}
    }
    let bytes = Array(source.snapshot.text.utf8)
    var lower = source.range.lowerBound
    while lower > 0, Self.isWhitespace(bytes[lower - 1]) { lower -= 1 }
    var upper = source.range.upperBound
    while upper < bytes.count, Self.isWhitespace(bytes[upper]) { upper += 1 }
    before = try SourceSlice(
      snapshot: source.snapshot,
      range: lower..<source.range.lowerBound
    )
    after = try SourceSlice(
      snapshot: source.snapshot,
      range: source.range.upperBound..<upper
    )
  }

  private static func isWhitespace(_ byte: UInt8) -> Bool {
    byte == 32 || byte == 9 || byte == 10 || byte == 13
  }
}

extension SourceProviding {
  /// The adjacent whitespace, ending before any neighbouring comment.
  ///
  /// A declaration includes its attached comments. A property or argument
  /// uses its complete declaration or argument. Other models use their captured
  /// source range.
  /// - Complexity: O(n), where n is the length of the source file.
  public var spacing: SourceSpacing {
    get throws { try SourceSpacing(around: self) }
  }
}

/// The whitespace to write between source elements.
public enum SourceWhitespace: String, CaseIterable, Sendable, Hashable {
  /// No whitespace.
  case none
  /// One space.
  case space
  /// One line ending followed by the existing indentation.
  case newline
  /// Two line endings followed by the existing indentation.
  case blankLine
}

extension SourceSlice {
  /// Returns a whitespace replacement with the source's line endings.
  ///
  /// A line ending retains the indentation after the replaced whitespace.
  /// For an inline region, it uses the current line's indentation.
  /// - Throws: ``SourceError/syntaxMismatch`` for a non-whitespace slice, or
  ///   ``SourceLayoutReplacementError/ambiguousTrivia`` when a replacement
  ///   would remove the line ending that terminates a line comment.
  public func replacement(with whitespace: SourceWhitespace) throws
    -> SourceFix
    .Edit
  {
    guard text.utf8.allSatisfy({ $0 == 32 || $0 == 9 || $0 == 10 || $0 == 13 })
    else {
      throw SourceError.syntaxMismatch
    }
    if whitespace == .none || whitespace == .space,
       text.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }),
       hasPrecedingLineComment
    {
      throw SourceLayoutReplacementError.ambiguousTrivia
    }
    let replacement: String
    switch whitespace {
    case .none: replacement = ""
    case .space: replacement = " "
    case .newline, .blankLine:
      let ending = snapshot.lineEnding
      let prefix = String(
        decoding: snapshot.text.utf8.prefix(range.upperBound),
        as: UTF8.self
      )
      let line =
        prefix.split(omittingEmptySubsequences: false) {
          $0 == "\n" || $0 == "\r" || $0 == "\r\n"
        }.last ?? ""
      let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
      replacement = (whitespace == .blankLine ? ending + ending : ending) +
        indentation
    }
    return self.replacement(with: replacement)
  }
}

extension SourceSlice {
  private var hasPrecedingLineComment: Bool {
    let tree = snapshot.swiftLanguageMode.parse(snapshot.text)
    func containsComment(_ trivia: Trivia, startingAt start: Int) -> Bool {
      var offset = start
      for piece in trivia {
        let lowerBound = offset
        offset += piece.sourceLength.utf8Length
        if lowerBound <= range.lowerBound, range.lowerBound <= offset {
          switch piece {
          case .lineComment, .docLineComment: return true
          default: break
          }
        }
      }
      return false
    }
    return tree.tokens(viewMode: .sourceAccurate).contains { token in
      containsComment(
        token.leadingTrivia,
        startingAt: token.position.utf8Offset
      )
        || containsComment(
          token.trailingTrivia,
          startingAt: token.endPositionBeforeTrailingTrivia.utf8Offset
        )
    }
  }
}
