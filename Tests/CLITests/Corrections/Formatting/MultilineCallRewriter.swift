import BylawsSyntax

final class MultilineCallRewriter: SyntaxRewriter {
  private let maximumLineLength: Int?

  init(maximumLineLength: Int? = nil) {
    self.maximumLineLength = maximumLineLength
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
    var parent = node.parent
    while let wrapper = parent,
          wrapper.is(TryExprSyntax.self) || wrapper.is(AwaitExprSyntax.self)
    {
      parent = wrapper.parent
    }
    guard parent?.is(CodeBlockItemSyntax.self) == true
      || parent?.is(InitializerClauseSyntax.self) == true,
      node.arguments.count > 1,
      let leftParen = node.leftParen,
      let rightParen = node.rightParen,
      let firstToken = node.firstToken(viewMode: .sourceAccurate),
      !node.hasError,
      !node.arguments.description.contains(where: \.isNewline),
      leftParen.trailingTrivia.allSatisfy(\.isWhitespace),
      rightParen.leadingTrivia.allSatisfy(\.isWhitespace),
      node.arguments.tokens(viewMode: .sourceAccurate).allSatisfy({
        $0.leadingTrivia.allSatisfy(\.isWhitespace)
          && $0.trailingTrivia.allSatisfy(\.isWhitespace)
          && $0.tokenKind != .multilineStringQuote
      }),
      exceedsMaximumLineLength(node)
    else { return super.visit(node) }

    let visited = super.visit(node).cast(FunctionCallExprSyntax.self)
    var prepared = visited
    prepared.leftParen?.trailingTrivia = []
    var hasLabel = false
    prepared
      .arguments = LabeledExprListSyntax(visited.arguments.enumerated().map {
        index, original in
        var argument = original
        hasLabel = hasLabel || argument.label != nil
        if argument.label != nil {
          argument.expression = expandedCollection(argument.expression)
        }
        argument.leadingTrivia = index == 0 || hasLabel ? .newline : .space
        argument.trailingTrivia = []
        return argument
      })
    prepared.rightParen?.leadingTrivia = .newline

    let indentation = firstToken.indentationOfLine
    let lineBreak = node.leadingTrivia.first(where: \.isNewline)
      ?? node.root.tokens(viewMode: .sourceAccurate).lazy
      .flatMap { $0.leadingTrivia + $0.trailingTrivia }
      .first(where: \.isNewline)
    let usesCRLF = if case .carriageReturnLineFeeds = lineBreak { true }
    else { false }
    let formatted = prepared.formatted(using: CallFormat(
      indentation: indentation, usesCRLF: usesCRLF
    )).cast(FunctionCallExprSyntax.self)
    var result = visited
    result.leftParen?.trailingTrivia = []
    result.arguments = formatted.arguments
    let newline: Trivia = usesCRLF ? .carriageReturnLineFeeds(1) : .newline
    result.rightParen?.leadingTrivia = newline + indentation
    return ExprSyntax(result)
  }

  private func exceedsMaximumLineLength(_ node: FunctionCallExprSyntax)
    -> Bool
  {
    guard let maximumLineLength else { return true }
    let converter = SourceLocationConverter(fileName: "", tree: node.root)
    let line = converter.location(for: node.positionAfterSkippingLeadingTrivia)
      .line
    return converter.sourceLines[line - 1].prefix { !$0.isNewline }.count
      > maximumLineLength
  }

  private func expandedCollection(_ expression: ExprSyntax) -> ExprSyntax {
    if var array = expression.as(ArrayExprSyntax.self),
       !array.elements.isEmpty
    {
      array.leftSquare.trailingTrivia = []
      array.elements = ArrayElementListSyntax(array.elements.map {
        var element = $0
        element.leadingTrivia = .newline
        element.trailingTrivia = []
        return element
      })
      array.rightSquare.leadingTrivia = .newline
      return ExprSyntax(array)
    }
    if var dictionary = expression.as(DictionaryExprSyntax.self),
       let elements = dictionary.content.as(DictionaryElementListSyntax.self),
       !elements.isEmpty
    {
      dictionary.leftSquare.trailingTrivia = []
      dictionary.content = .elements(DictionaryElementListSyntax(elements.map {
        var element = $0
        element.leadingTrivia = .newline
        element.trailingTrivia = []
        return element
      }))
      dictionary.rightSquare.leadingTrivia = .newline
      return ExprSyntax(dictionary)
    }
    return expression
  }

  private final class CallFormat: BasicFormat {
    private let usesCRLF: Bool

    init(indentation: Trivia, usesCRLF: Bool) {
      self.usesCRLF = usesCRLF
      super.init(indentationWidth: .spaces(2), initialIndentation: indentation)
    }

    override func visit(_ token: TokenSyntax) -> TokenSyntax {
      var result = super.visit(token)
      guard usesCRLF else { return result }
      result.leadingTrivia = convertingLineBreaks(result.leadingTrivia)
      result.trailingTrivia = convertingLineBreaks(result.trailingTrivia)
      return result
    }

    private func convertingLineBreaks(_ trivia: Trivia) -> Trivia {
      Trivia(pieces: trivia.map {
        if case let .newlines(count) = $0 {
          return .carriageReturnLineFeeds(count)
        }
        return $0
      })
    }
  }
}
