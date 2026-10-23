import BylawsSemantics
import Testing

@Suite("Source spacing")
struct SourceSpacingTests {
  @Test("Property spacing includes declaration keyword")
  func properties() throws {
    let file = try FileCollector.collect(
      source: """
      func work() {
        log()
        let value = 1
      }
      """, path: "/virtual/Spacing.swift"
    )
    let property = try #require(file.variableBindings.first)
    let statement = try #require(
      file.syntaxNodes(of: .codeBlock).first?
        .statements.last
    )
    let edit = try statement.spacing.before.replacement(with: .blankLine)
    #expect(edit.source.text == "\n  ")
    #expect(edit.replacement == "\n\n  ")
    #expect(try property.source.text == "value = 1")
  }

  @Test("Spacing retains leading documentation")
  func documentation() throws {
    let file = try FileCollector.collect(
      source: """
      struct Store {
        let first: Int
        /// The next value.
        let second: Int
      }
      """, path: "/virtual/Spacing.swift"
    )
    let property = file.structs[0].properties[1]
    let edit = try property.spacing.before.replacement(with: .blankLine)
    #expect(edit.source.text == "\n  ")
    #expect(edit.replacement == "\n\n  ")
    #expect(edit.source.range.upperBound < (property.location.utf8Offset ?? 0))
  }

  @Test("Spacing stops before comments")
  func comments() throws {
    let file = try FileCollector.collect(
      source: "let value = 1 // Keep this value.\n",
      path: "/virtual/Spacing.swift"
    )
    let source = try file.variableBindings[0].source
    let edit = try source.spacing.after.replacement(with: .newline)
    #expect(edit.source.text == " ")
    #expect(edit.replacement == "\n")
  }

  @Test("Line-comment endings survive whitespace corrections")
  func commentEndings() throws {
    let file = try FileCollector.collect(
      source: "// Keep this value.\nlet value = 1",
      path: "/virtual/Spacing.swift"
    )
    let source = try file.syntaxNodes(of: .variableDeclaration)[0].source
    #expect(throws: SourceLayoutReplacementError.ambiguousTrivia) {
      try source.spacing.before.replacement(with: .space)
    }
    #expect(throws: SourceLayoutReplacementError.ambiguousTrivia) {
      try source.spacing.before.replacement(with: .none)
    }
  }

  @Test("Expression spacing retains argument labels")
  func expressionBoundaries() throws {
    let file = try FileCollector.collect(
      source: "consume(label: foo())",
      path: "/virtual/Spacing.swift"
    )
    let call = try #require(
      file.syntaxNodes(of: .functionCall)
        .first { $0.call?.calledExpression == "foo" }
    )
    let spacing = try call.spacing.before
    #expect(spacing.text == " ")
    #expect(spacing.range.upperBound == call.location.utf8Offset)
  }

  @Test(
    "Whitespace replacements preserve line endings and tabs",
    arguments: ["\n", "\r\n", "\r"]
  )
  func lineEndings(ending: String) throws {
    let file = try FileCollector.collect(
      source: "struct Store {\(ending)\tlet first: Int\(ending)\tlet second: Int\(ending)}",
      path: "/virtual/Spacing.swift"
    )
    let edit = try file.structs[0].properties[1].spacing.before
      .replacement(with: .blankLine)
    #expect(edit.source.text == "\(ending)\t")
    #expect(edit.replacement == "\(ending)\(ending)\t")
  }
}
