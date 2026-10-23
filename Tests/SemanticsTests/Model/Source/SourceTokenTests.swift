import BylawsSemantics
import Testing

@Suite("Captured lexical source")
struct SourceTokenTests {
  @Test("Operator spacing preserves string and regex contents")
  func operatorSpacing() throws {
    let text = #"""
    let note = "left+right // keep"
    let pattern = #/left+right/#
    let result = left+right
    """#
    let file = try collect(text)
    let operators = try file.tokens
      .filter { $0.kind == .binaryOperator && $0.text == "+" }
    let addition = try #require(operators.first)
    let edits = [
      try addition.spacing.before.replacement(with: .space),
      try addition.spacing.after.replacement(with: .space),
    ]

    #expect(operators.count == 1)
    #expect(try file.tokens
      .contains { $0.kind == .stringSegment && $0.text == "left+right // keep"
      })
    #expect(try file.tokens.contains { $0.kind == .regexLiteralPattern })
    #expect(applying(edits, to: text) == #"""
    let note = "left+right // keep"
    let pattern = #/left+right/#
    let result = left + right
    """#)
  }

  @Test("Token neighbours retain original file context")
  func neighbours() throws {
    let file = try collect("let first = 1\nlet second = 2")
    let literal = try #require(file.syntaxNodes(of: .integerLiteral).first)
    let token = try #require(literal.tokens.first)

    #expect(token.text == "1")
    #expect(token.previous?.kind == .equal)
    #expect(token.next?.kind == .keyword)
    #expect(token.next?.text == "let")
    #expect(try file.tokens.first?.previous == nil)
    #expect(try file.tokens.last?.next == nil)
  }

  @Test("Partial token slices omit incomplete tokens")
  func partialToken() throws {
    let file = try collect("let alphabet = 1")
    let identifier = try #require(file.tokens.first { $0.text == "alphabet" })
    let part = try identifier.source.slice(1..<4)

    #expect(part.text == "lph")
    #expect(try part.tokens.isEmpty)
    #expect(try part.trivia.isEmpty)
    #expect(try identifier.source.tokens.map(\.text) == ["alphabet"])
    #expect(try file.source.slice(0..<0).tokens.isEmpty)
  }

  @Test("Unicode offsets preserve exact source")
  func unicodeRanges() throws {
    let text = "let café = first⊕second\n"
    let file = try collect(text)
    let tokens = try file.tokens
    let identifier = try #require(tokens.first { $0.text == "café" })
    let operation = try #require(tokens.first { $0.text == "⊕" })
    let edit = operation.source.replacement(with: "+")

    #expect(identifier.source.range == 4..<9)
    #expect(operation.kind == .binaryOperator)
    #expect(operation.source.range.count == 3)
    #expect(applying([edit], to: text) == "let café = first+second\n")
    #expect(throws: SourceError.rangeOutOfBounds) {
      try identifier.source.slice(0..<4)
    }
  }

  @Test("Brace spacing selects punctuation rather than literal text")
  func bracePlacement() throws {
    let text = "func render() { print(\"{ keep }\") }"
    let file = try collect(text)
    let braces = try file.tokens.filter { $0.kind == .leftBrace }
    let brace = try #require(braces.first)
    let edit = try brace.spacing.before.replacement(with: .newline)

    #expect(braces.count == 1)
    #expect(applying([edit], to: text) ==
      "func render()\n{ print(\"{ keep }\") }")
  }

  @Test("Operator kinds retain prefix and infix roles")
  func operatorKinds() throws {
    let file = try collect("let value = -first + second")
    let operators = try file.tokens.filter {
      $0.kind == .prefixOperator || $0.kind == .binaryOperator
    }

    #expect(operators.map(\.text) == ["-", "+"])
    #expect(operators.map(\.kind) == [.prefixOperator, .binaryOperator])
  }

  @Test("Token trivia retains original ownership")
  func tokenTrivia() throws {
    let file = try collect("/// Stored count.\nlet count = 1 // retained\n")
    let tokens = try file.tokens
    let declaration = try #require(tokens.first)
    let literal = try #require(tokens.last)

    #expect(declaration.leadingTrivia.filter(\.isComment)
      .map(\.kind) == [.docLineComment])
    #expect(declaration.leadingTrivia.filter(\.isComment)
      .map(\.text) == ["/// Stored count."])
    #expect(literal.trailingTrivia.filter(\.isComment)
      .map(\.text) == ["// retained"])
    #expect(try file.trivia.filter(\.isComment).map(\.text) == [
      "/// Stored count.",
      "// retained",
    ])
  }

  @Test("File trivia includes final and comment-only input", arguments: [
    "// Last comment", "/* Last comment */", "let value = 1\n// Last comment",
  ])
  func finalComments(text: String) throws {
    let file = try collect(text)
    let comments = try file.trivia.filter(\.isComment)
    let comment = try #require(comments.last)

    #expect(comments.count == 1)
    #expect(comment.source.range.upperBound == text.utf8.count)
    #expect(comment.text.hasSuffix("comment") || comment.text
      .hasSuffix("comment */"))
    #expect(try comment.tokens.isEmpty)
    #expect(try collect("").tokens.isEmpty)
    #expect(try collect("").trivia.isEmpty)
  }

  @Test("Comment edits select trivia without matching string content")
  func commentReplacement() throws {
    let text = "let note = \"// TODO: keep\"\n// TODO: revise\n"
    let file = try collect(text)
    let comments = try file.trivia.filter { $0.kind == .lineComment }
    let comment = try #require(comments.first)
    let edit = comment.source.replacement(with: "// Revised.")

    #expect(comments.count == 1)
    #expect(applying([edit], to: text) ==
      "let note = \"// TODO: keep\"\n// Revised.\n")
    #expect(try comment.source.slice(1..<4).trivia.isEmpty)
  }

  @Test("Whitespace trivia retains line-ending spelling", arguments: [
    ("\n", SourceTrivia.Kind.newlines),
    ("\r\n", .carriageReturnLineFeeds),
    ("\r", .carriageReturns),
  ])
  func lineEndings(ending: String, kind: SourceTrivia.Kind) throws {
    let file = try collect("let first = 1\(ending)\tlet second = 2")
    let trivia = try file.trivia

    #expect(trivia.filter { $0.kind == kind }.map(\.text) == [ending])
    #expect(trivia.filter { $0.kind == .tabs }.map(\.text) == ["\t"])
  }

  private func collect(_ text: String) throws -> SourceFile {
    try FileCollector.collect(source: text, path: "/virtual/Lexical.swift")
  }

  private func applying(_ edits: [SourceFix.Edit], to text: String) -> String {
    var bytes = Array(text.utf8)
    for edit in edits
      .sorted(by: { $0.source.range.lowerBound > $1.source.range.lowerBound })
    {
      bytes.replaceSubrange(edit.source.range, with: edit.replacement.utf8)
    }
    return String(decoding: bytes, as: UTF8.self)
  }
}
