import BylawsSemantics
import Testing

@Suite("Source syntax nodes")
struct SourceNodeTests {
  @Test("Nodes retain structure and locations")
  func structure() throws {
    let file = try FileCollector.collect(
      source: """
      func run() async {
        defer { lock.unlock() }
        await Task.detached { work() }.value
      }
      """,
      path: "/virtual/Tasks.swift"
    )

    let nodes = file.syntaxNodes(
      of: .sourceFile,
      .functionCall,
      .awaitExpression,
      .closureExpression,
      .functionDeclaration
    )
    let detachedCall = try #require(nodes.first {
      $0.kind == .functionCall && $0.text.hasPrefix("Task.detached")
    })
    let workCall = try #require(nodes.first {
      $0.kind == .functionCall && $0.text == "work()"
    })

    #expect(nodes.first?.kind == .sourceFile)
    #expect(detachedCall.location.line == 3)
    #expect(detachedCall.call?.references("Task.detached") == true)
    #expect(detachedCall.expression?.calledExpression?
      .referenceName == "detached")
    #expect(detachedCall.ancestors.contains { $0.kind == .awaitExpression })
    #expect(workCall.ancestors.contains { $0.kind == .closureExpression })
    #expect(workCall.ancestors.contains { $0.kind == .functionDeclaration })
  }

  @Test("Descendants follow source order")
  func descendants() throws {
    let file = try FileCollector.collect(
      source: "let values = [first(), second()]",
      path: "/virtual/Values.swift"
    )
    let root = try #require(file.syntaxNodes(of: .sourceFile).first)
    let calls = root.descendants.filter { $0.kind == .functionCall }

    #expect(calls.map(\.text) == ["first()", "second()"])
  }

  @Test("Language mode applies during syntax queries")
  func languageMode() throws {
    let file = try FileCollector.collect(
      source: """
      @available (swift, obsoleted: 1.0)
      func legacy() {}
      """,
      path: "/virtual/Legacy.swift",
      swiftLanguageMode: .v5
    )

    #expect(!file.syntaxNodes(of: .functionDeclaration).isEmpty)
  }
}
