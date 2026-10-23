import BylawsSemantics
import Testing

@Suite("Source list indentation")
struct SourceListIndentationTests {
  @Test(
    "Multiline groups retain original indentation",
    arguments: ["    ", "      ", "\t"]
  )
  func multilineIndentation(indent: String) throws {
    let source = """
    struct Store {
    \(indent)let zebra = build(
    \(indent)\(indent)value: 1
    \(indent))
    \(indent)let apple = build(
    \(indent)\(indent)value: 2
    \(indent))
    }
    """
    let file = try collect(source)
    let members = try #require(file.syntaxNodes(of: .structDeclaration).first)
      .members
    let fix = try members.replacement {
      Group(where: { _ in true }).sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
    let corrected = try applying(fix, to: file)

    #expect(corrected == """
    struct Store {
    \(indent)let apple = build(
    \(indent)\(indent)value: 2
    \(indent))
    \(indent)let zebra = build(
    \(indent)\(indent)value: 1
    \(indent))
    }
    """)
    let parsed = try collect(corrected)
    let correctedMembers = try #require(parsed
      .syntaxNodes(of: .structDeclaration).first).members
    let second = try correctedMembers.replacement {
      Group(where: { _ in true }).sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
    #expect(second.edits.isEmpty)
  }

  @Test(
    "Multiline groups retain indentation around unmatched members",
    arguments: ["    ", "      ", "\t"]
  )
  func anchoredMultilineIndentation(indent: String) throws {
    let source = """
    struct Store {
    \(indent)var marker = 0

    \(indent)let zebra = build(
    \(indent)\(indent)value: 1
    \(indent))
    \(indent)let apple = build(
    \(indent)\(indent)value: 2
    \(indent))

    \(indent)var last = 0
    }
    """
    let file = try collect(source)
    let members = try #require(file.syntaxNodes(of: .structDeclaration).first)
      .members
    let fix = try members.replacement {
      Group(where: { $0.property?.isConstant == true })
        .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    #expect(try applying(fix, to: file) == """
    struct Store {
    \(indent)var marker = 0

    \(indent)let apple = build(
    \(indent)\(indent)value: 2
    \(indent))
    \(indent)let zebra = build(
    \(indent)\(indent)value: 1
    \(indent))

    \(indent)var last = 0
    }
    """)
  }

  @Test(
    "Grouped multiline strings retain text and indentation",
    arguments: ["    ", "      ", "\t"]
  )
  func multilineStrings(indent: String) throws {
    let source = "struct Store {\n\(indent)let zebra = \"\"\"\n\(indent)\(indent)zebra\n\(indent)\"\"\"\n\(indent)let apple = \"\"\"\n\(indent)\(indent)apple\n\(indent)\"\"\"\n}"
    let file = try collect(source)
    let members = try #require(file.syntaxNodes(of: .structDeclaration).first)
      .members
    let fix = try members.replacement {
      Group(where: { _ in true }).sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
    let corrected = try applying(fix, to: file)

    #expect(corrected ==
      "struct Store {\n\(indent)let apple = \"\"\"\n\(indent)\(indent)apple\n\(indent)\"\"\"\n\(indent)let zebra = \"\"\"\n\(indent)\(indent)zebra\n\(indent)\"\"\"\n}")
    let parsed = try collect(corrected)
    #expect(parsed.variableBindings.compactMap { $0.initialValue?.stringValue }
      == [indent + "apple", indent + "zebra"])
  }

  private func collect(_ source: String) throws -> SourceFile {
    try FileCollector.collect(
      source: source,
      path: "/virtual/SourceLists.swift"
    )
  }

  private func applying(
    _ fix: SourceFix,
    to file: SourceFile
  ) throws -> String {
    try file.source.replacement(applying: fix.edits).replacement
  }
}
