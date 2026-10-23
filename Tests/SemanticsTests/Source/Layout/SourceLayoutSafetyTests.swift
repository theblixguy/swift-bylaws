import BylawsSemantics
import Testing

@Suite("Source layout safety")
struct SourceLayoutSafetyTests {
  @Test("Trailing comments stop property ordering")
  func trailingComments() throws {
    let file =
      try collect(
        "struct Store {\n  let zebra: Int // Keep with the last property.\n  let apple: Int\n}"
      )
    let properties = file.structs[0].properties

    #expect(throws: SourceLayoutReplacementError.ambiguousTrivia) {
      try properties.replacement { properties.reversed() }
    }
  }

  @Test("CRLF keeps adjacent declaration comments attached")
  func crlfComments() throws {
    let file = try collect(
      "struct Store {\r\n  /// Last property.\r\n  let zebra: Int\r\n  /// First property.\r\n  let apple: Int\r\n}"
    )
    let properties = file.structs[0].properties
    let edit = try properties.replacement { properties.reversed() }

    #expect(
      applying(edit)
        == "struct Store {\r\n  /// First property.\r\n  let apple: Int\r\n  /// Last property.\r\n  let zebra: Int\r\n}"
    )
  }

  @Test("Partial attribute lists stop replacement")
  func partialAttributeList() throws {
    let file = try collect("@First @Second @Third class Store {}")
    let attributes = file.classes[0].attributes.prefix(2)

    #expect(throws: SourceLayoutReplacementError.noncontiguousElements) {
      try attributes.replacement { Line { attributes.reversed() } }
    }
  }

  @Test("Partial argument lists stop comma changes")
  func partialArgumentList() throws {
    let file = try collect("let result = send(first: 1, second: 2, third: 3)")
    let arguments = file.calls[0].arguments.prefix(2)

    #expect(throws: SourceLayoutReplacementError.noncontiguousElements) {
      try arguments.replacement { arguments.reversed() }
    }
  }

  @Test("Semicolon-separated declarations stop replacement")
  func semicolonDeclarations() throws {
    let file = try collect("struct Store { let zebra: Int; let apple: Int }")
    let properties = file.structs[0].properties

    #expect(throws: SourceLayoutReplacementError.unsupportedElement) {
      try properties.replacement { properties.reversed() }
    }
  }

  @Test("Multiline strings keep relative indentation during ordering")
  func multilineString() throws {
    let file = try collect(
      #"""
      struct Store {
        let zebra = """
          first
            second
          """
        let apple = 1
      }
      """#
    )
    let properties = file.structs[0].properties
    let edit = try properties.replacement { properties.reversed() }

    #expect(
      applying(edit) == #"""
      struct Store {
        let apple = 1
        let zebra = """
          first
            second
          """
      }
      """#
    )
  }

  @Test("Partial indentation changes stop multiline string replacements")
  func partialMultilineStringIndentation() throws {
    let source = "struct Store {\n  let text = \"\"\"\n  hello\n\"\"\"\n}"
    let file = try collect(source)
    let properties = file.structs[0].properties
    let unchanged = try properties.replacement { properties }

    #expect(file.variableBindings.first?.initialValue?.stringValue == "  hello")
    #expect(applying(unchanged) == source)
    #expect(throws: SourceLayoutError.inconsistentIndentation) {
      try properties.replacement {
        Indent {
          Newline()
          properties
        }
        Newline()
      }
    }
  }

  @Test("Uniform indentation changes preserve multiline string values")
  func uniformMultilineStringIndentation() throws {
    let file = try collect(
      #"""
      struct Store {
        let text = """
          hello
            world
          """
      }
      """#
    )
    let properties = file.structs[0].properties
    let edit = try properties.replacement {
      Indent {
        Newline()
        properties
      }
      Newline()
    }
    let corrected = applying(edit)

    #expect(
      corrected == #"""
      struct Store {
          let text = """
            hello
              world
            """
      }
      """#
    )
    let value = try #require(collect(corrected).variableBindings.first?
      .initialValue?.stringValue)
    #expect(value == "hello\n  world")
    #expect(value == file.variableBindings.first?.initialValue?.stringValue)
  }

  @Test("Hard lines reject multiline attribute arguments")
  func multilineAttribute() throws {
    let file =
      try collect("@First(\n  values: [1, 2]\n)\n@Second class Store {}")
    let attributes = file.classes[0].attributes

    #expect(throws: SourceLayoutError.lineContainsNewline) {
      try attributes.replacement { Line { attributes } }
    }
  }

  @Test("Empty sections preserve source inventory")
  func emptySections() throws {
    let file = try collect("struct Store {\n  let count = 1\n}")
    let properties = file.structs[0].properties
    let edit = try properties.replacement {
      BlankLine()
      properties.filter { $0.name == "absent" }
      BlankLine()
      properties
      BlankLine()
    }

    #expect(applying(edit) == file.sourceText)
  }

  @Test("Trailing argument commas follow reordered last element")
  func trailingArgumentComma() throws {
    let file = try collect("let result = send(first: 1, second: 2,)")
    let arguments = file.calls[0].arguments
    let edit = try arguments.replacement { arguments.reversed() }

    #expect(applying(edit) == "let result = send(second: 2, first: 1,)")
  }

  @Test("Wrapping measures original argument column")
  func finalWrapWidth() throws {
    let file = try collect("func update() {\n    f(aa, bbb, cccc)\n}")
    let arguments = file.calls[0].arguments
    let edit = try arguments.replacement {
      Wrap(width: 14) { arguments }
    }

    #expect(applying(edit) ==
      "func update() {\n    f(aa, bbb,\n        cccc)\n}")
  }

  @Test("File headers stay outside declaration ordering")
  func fileHeader() throws {
    let file =
      try collect("// Copyright Example.\nfunc zebra() {}\nfunc apple() {}")
    let functions = file.functions

    #expect(throws: SourceLayoutReplacementError.ambiguousTrivia) {
      try functions.replacement { functions.reversed() }
    }
  }

  @Test(
    "Formatting controls stop declaration ordering",
    arguments: [
      "swiftformat:disable", "swiftlint:disable all",
    ]
  )
  func formattingControl(directive: String) throws {
    let file =
      try collect(
        "struct Store {\n  // \(directive)\n  let zebra: Int\n  let apple: Int\n}"
      )
    let properties = file.structs[0].properties

    #expect(throws: SourceLayoutReplacementError.ambiguousTrivia) {
      try properties.replacement { properties.reversed() }
    }
  }

  @Test("Empty lines preserve inline argument layout")
  func emptyLine() throws {
    let file = try collect("let result = send(first: 1, second: 2)")
    let arguments = file.calls[0].arguments
    let edit = try arguments.replacement {
      Line { arguments.filter { _ in false } }
      arguments
    }

    #expect(applying(edit) == file.sourceText)
  }

  private func collect(_ source: String) throws -> SourceFile {
    try FileCollector.collect(
      source: source,
      path: "/virtual/LayoutSafety.swift"
    )
  }

  private func applying(_ edit: SourceFix.Edit) -> String {
    var bytes = Array(edit.source.file.text.utf8)
    bytes.replaceSubrange(edit.source.range, with: edit.replacement.utf8)
    return String(decoding: bytes, as: UTF8.self)
  }
}
