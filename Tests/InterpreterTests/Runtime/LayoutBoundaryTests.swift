import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import Testing

@Suite("Portable layout boundaries")
struct LayoutBoundaryTests {
  @Test(
    "Empty attribute edits retain adjacent line boundaries",
    arguments: [false, true]
  )
  func emptyAttributeEdit(emptyFirst: Bool) async throws {
    let project = try rulesProject(
      rules: """
      Rule("attributes") {
        try await app.syntaxNodes(of: .classDeclaration).violations("Place attributes on a line") { declaration in
          if declaration.name == "Store" {
            let attributes = declaration.attributes
            try attributes.replacement {
              if \(emptyFirst) {
                try attributes[0].source.replacement(with: "")
                Line { attributes[1] }
              } else {
                Line { attributes[0] }
                try attributes[1].source.replacement(with: "")
              }
            }
          }
        }
      }
      """,
      sources: [
        "Sources/Store.swift": "class Outer {\n\n  @First @Second class Store {}\n}",
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let edit = try #require(findings.violations.fixes.first??.edits.first)
    let remaining = emptyFirst ? "Second" : "First"
    var bytes = Array(edit.source.file.text.utf8)
    bytes.replaceSubrange(edit.source.range, with: edit.replacement.utf8)

    #expect(findings.violations.count == 1)
    #expect(String(decoding: bytes, as: UTF8.self) ==
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
  ) async throws {
    let project = try rulesProject(
      rules: """
      Rule("attributes") {
        try await app.syntaxNodes(of: .classDeclaration).violations("Remove attributes") { declaration in
          if declaration.name == "Inner" {
            let attributes = declaration.attributes
            try attributes.replacement {
              try attributes[0].source.replacement(with: "")
              if \(insertsNewline) { Newline() }
            }
          }
        }
      }
      """,
      sources: ["Sources/Store.swift": source]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let edit = try #require(findings.violations.fixes.first??.edits.first)
    var bytes = Array(edit.source.file.text.utf8)
    bytes.replaceSubrange(edit.source.range, with: edit.replacement.utf8)

    #expect(findings.violations.count == 1)
    #expect(String(decoding: bytes, as: UTF8.self) == expected)
  }
}
