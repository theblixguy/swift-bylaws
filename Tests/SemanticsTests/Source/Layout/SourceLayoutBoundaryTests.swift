import BylawsSemantics
import Testing

@Suite("Source layout boundaries")
struct SourceLayoutBoundaryTests {
  @Test(
    "Empty attribute edits retain adjacent line boundaries",
    arguments: [false, true]
  )
  func emptyAttributeEdit(emptyFirst: Bool) throws {
    let file =
      try collect("class Outer {\n\n  @First @Second class Store {}\n}")
    let declaration = try #require(file.syntaxNodes(of: .classDeclaration)
      .first { $0.name == "Store" })
    let attributes = declaration.attributes
    let edit = try attributes.replacement {
      if emptyFirst {
        try attributes[0].source.replacement(with: "")
        Line { attributes[1] }
      } else {
        Line { attributes[0] }
        try attributes[1].source.replacement(with: "")
      }
    }
    let remaining = emptyFirst ? "Second" : "First"

    #expect(applying(edit) ==
      "class Outer {\n  @\(remaining)\n  class Store {}\n}")
  }

  @Test("Deleting all attributes retains one source boundary", arguments: [
    (
      "class Outer {\n  let marker = 0\n  @Only class Inner {}\n}", false,
      "class Outer {\n  let marker = 0\n  class Inner {}\n}"
    ),
    (
      "class Outer { @Only class Inner {} }",
      false,
      "class Outer { class Inner {} }"
    ),
    (
      "class Outer {\n  let marker = 0; @Only class Inner {}\n}", true,
      "class Outer {\n  let marker = 0;\n  class Inner {}\n}"
    ),
    ("@Only class Inner {}", false, "class Inner {}"),
    ("@Only class Inner {}", true, "\nclass Inner {}"),
  ])
  func deletedAttributes(
    source: String,
    insertsNewline: Bool,
    expected: String
  ) throws {
    let file = try collect(source)
    let declaration = try #require(file.syntaxNodes(of: .classDeclaration)
      .first { $0.name == "Inner" })
    let attributes = declaration.attributes
    let edit = try attributes.replacement {
      try attributes[0].source.replacement(with: "")
      if insertsNewline { Newline() }
    }

    #expect(applying(edit) == expected)
  }

  @Test("Explicit newlines format vertical list boundaries")
  func verticalEdges() throws {
    let file = try collect("struct Store { let first: Int\nlet second: Int }")
    let properties = file.structs[0].properties
    let edit = try properties.replacement {
      Newline()
      properties
      Newline()
    }
    #expect(applying(edit) ==
      "struct Store {\n  let first: Int\n  let second: Int\n}")
  }

  @Test("Outer indentation includes first argument line")
  func leadingIndentation() throws {
    let file = try collect("let result = send(first: 1, second: 2)")
    let arguments = try #require(file.calls.first).arguments
    let edit = try arguments.replacement {
      Indent {
        for argument in arguments { Line { argument } }
      }
    }
    #expect(applying(edit) ==
      "let result = send(\n    first: 1,\n    second: 2\n)")
  }

  @Test(
    "Attribute layouts preserve line endings and indentation",
    arguments: ["\n", "\r\n", "\r"]
  )
  func lineEndings(ending: String) throws {
    let file =
      try collect(
        "struct Container {\(ending)\t@MainActor\(ending)\t@Observable class Store {}\(ending)}"
      )
    let attributes = file.classes[0].attributes
    let edit = try attributes.replacement { Line { attributes.reversed() } }
    #expect(
      applying(edit)
        ==
        "struct Container {\(ending)\t@Observable @MainActor\(ending)\tclass Store {}\(ending)}"
    )
  }

  private func collect(_ source: String) throws -> SourceFile {
    try FileCollector.collect(source: source, path: "/virtual/Layout.swift")
  }

  private func applying(_ edit: SourceFix.Edit) -> String {
    var bytes = Array(edit.source.file.text.utf8)
    bytes.replaceSubrange(edit.source.range, with: edit.replacement.utf8)
    return String(decoding: bytes, as: UTF8.self)
  }
}
