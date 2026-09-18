import BylawsSemantics
import BylawsSyntax
import Testing

@Suite("Source syntax sessions")
struct SourceSyntaxSessionTests {
  @Test(
    "Syntax lookup resolves a line and byte column",
    arguments: ["\n", "\r\n", "\r"]
  )
  func lineAndColumn(_ newline: String) throws {
    let path = "/virtual/App.swift"
    let file = try FileCollector.collect(
      source: "struct First {}\(newline)struct Second {}", path: path
    )
    let reference = MockReference(location: DeclarationLocation(
      filePath: path,
      line: 2,
      column: 8
    ))
    let name = file
      .withSyntax(of: reference, as: StructDeclSyntax.self) { $0.name.text }
    #expect(name == "Second")
  }

  private struct MockReference: Located {
    let location: DeclarationLocation
  }

  @Test("One session resolves several declarations from its file")
  func resolvesSeveralDeclarations() throws {
    let file = try FileCollector.collect(
      source: """
      struct Store {
        func reload() {}
      }
      """,
      path: "/virtual/App/Store.swift"
    )
    let store = try #require(file.structs.first)
    let reload = try #require(file.functions.first)

    let names = file.withSyntaxSession { session in
      let typeName = session.withSyntax(
        of: store,
        as: StructDeclSyntax.self
      ) { $0.name.text }
      let functionName = session.withSyntax(
        of: reload,
        as: FunctionDeclSyntax.self
      ) { $0.name.text }
      return [typeName, functionName]
    }

    #expect(names == ["Store", "reload"])
  }

  @Test("A session rejects a declaration from another file")
  func rejectsAnotherFile() throws {
    let first = try FileCollector.collect(
      source: "struct First {}",
      path: "/virtual/App/First.swift"
    )
    let second = try FileCollector.collect(
      source: "struct Second {}",
      path: "/virtual/App/Second.swift"
    )
    let secondDeclaration = try #require(second.structs.first)

    let name = first.withSyntaxSession { session in
      session.withSyntax(
        of: secondDeclaration,
        as: StructDeclSyntax.self
      ) { $0.name.text }
    }

    #expect(name == nil)
  }
}
