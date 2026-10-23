import BylawsSemantics
import Testing

@Suite("Syntax list indentation")
struct SourceSyntaxListIndentationTests {
  @Test("Header and body indentation remains stable", arguments: [
    (
      SourceNode.Kind.conditionList,
      "if first, second {}",
      "if\n  first,\n  second\n{}"
    ),
    (
      .genericRequirementList,
      "func pick<A, B>() where A: First, B: Second {}",
      "func pick<A, B>() where\n  A: First,\n  B: Second\n{}"
    ),
    (
      .inheritedTypeList,
      "struct Value: First, Second {}",
      "struct Value:\n  First,\n  Second\n{}"
    ),
    (
      .switchCaseList,
      "switch value { case .first: first()\ncase .second: second() }",
      "switch value {\n  case .first: first()\n  case .second: second()\n}"
    ),
    (
      .accessorList,
      "var value: Int { get { load() }\nset { save(newValue) } }",
      "var value: Int {\n    get { load() }\n    set { save(newValue) }\n}"
    ),
  ])
  func ownerIndentation(
    kind: SourceNode.Kind,
    source: String,
    expected: String
  ) throws {
    let file = try collect(source)
    let elements = try #require(file.syntaxNodes(of: kind).first).elements
    let edit = try elements.replacement {
      Newline()
      Indent {
        for element in elements { Line { element } }
      }
      Newline()
    }
    let result = applying(edit)
    #expect(result == expected)

    let corrected = try collect(result)
    let correctedElements = try #require(corrected.syntaxNodes(of: kind).first)
      .elements
    let repeated = try correctedElements.replacement {
      Newline()
      Indent {
        for element in correctedElements { Line { element } }
      }
      Newline()
    }
    #expect(applying(repeated) == expected)
  }

  @Test("Argument indentation uses stable surrounding source", arguments: [
    (
      "let value = send(first: 1, second: 2)",
      "let value = send(\n    first: 1,\n    second: 2\n)"
    ),
    (
      "func run() {\n    let value = send(first: 1, second: 2)\n}",
      "func run() {\n    let value = send(\n            first: 1,\n            second: 2\n    )\n}"
    ),
    (
      "func run() {\n\tlet value = send(first: 1, second: 2)\n}",
      "func run() {\n\tlet value = send(\n\t\t\tfirst: 1,\n\t\t\tsecond: 2\n\t)\n}"
    ),
  ])
  func argumentIndentation(source: String, expected: String) throws {
    let file = try collect(source)
    let arguments = try #require(file.calls.first { $0.name == "send" })
      .arguments
    let edit = try arguments.replacement {
      Indent {
        for argument in arguments { Line { argument } }
      }
    }
    let result = applying(edit)
    #expect(result == expected)

    let corrected = try collect(result)
    let correctedArguments = try #require(corrected.calls
      .first { $0.name == "send" })
      .arguments
    let repeated = try correctedArguments.replacement {
      Indent {
        for argument in correctedArguments { Line { argument } }
      }
    }
    #expect(applying(repeated) == expected)
  }

  @Test("Member indentation uses enclosing declaration on repeated runs")
  func memberIndentation() throws {
    let source = "struct Value { let first = 1\nlet second = 2 }"
    let expected = "struct Value {\n    let first = 1\n    let second = 2\n}"
    let file = try collect(source)
    let members = try #require(file.syntaxNodes(of: .structDeclaration).first)
      .members
    let edit = try members.replacement {
      Newline()
      Indent {
        for member in members { Line { member } }
      }
      Newline()
    }
    let result = applying(edit)
    #expect(result == expected)

    let corrected = try collect(result)
    let correctedMembers = try #require(corrected
      .syntaxNodes(of: .structDeclaration).first)
      .members
    let repeated = try correctedMembers.replacement {
      Newline()
      Indent {
        for member in correctedMembers { Line { member } }
      }
      Newline()
    }
    #expect(applying(repeated) == expected)
  }

  @Test("Statement indentation uses enclosing block on repeated runs")
  func statementIndentation() throws {
    let source = "func run() { first()\nsecond() }"
    let expected = "func run() {\n    first()\n    second()\n}"
    let file = try collect(source)
    let statements = try #require(file.syntaxNodes(of: .codeBlock).first)
      .statements
    let edit = try statements.replacement {
      Newline()
      Indent {
        for statement in statements { Line { statement } }
      }
      Newline()
    }
    let result = applying(edit)
    #expect(result == expected)

    let corrected = try collect(result)
    let correctedStatements = try #require(corrected.syntaxNodes(of: .codeBlock)
      .first)
      .statements
    let repeated = try correctedStatements.replacement {
      Newline()
      Indent {
        for statement in correctedStatements { Line { statement } }
      }
      Newline()
    }
    #expect(applying(repeated) == expected)
  }

  private func collect(_ source: String) throws -> SourceFile {
    try FileCollector.collect(
      source: source,
      path: "/virtual/Indentation.swift"
    )
  }

  private func applying(_ edit: SourceFix.Edit) -> String {
    var bytes = Array(edit.source.file.text.utf8)
    bytes.replaceSubrange(edit.source.range, with: edit.replacement.utf8)
    return String(decoding: bytes, as: UTF8.self)
  }
}
