import BylawsSemantics
import SwiftParser
import SwiftSyntax
import Testing

@Suite("Source rendering")
struct SourceRenderingTests {
  @Test("A declaration contains its own source text")
  func extractsSourceText() throws {
    let file = try FileCollector.collect(
      source: """
      /// A thing.
      final class Widget {
        // TODO: remove the legacy path.
        func legacy() {}
      }
      """,
      path: "/virtual/App/Widget.swift"
    )

    let widget = try #require(file.classes.first)
    #expect(widget.sourceText.hasPrefix("final class Widget"))
    #expect(widget.sourceText.contains("TODO"))
    #expect(!widget.sourceText.contains("/// A thing."))
  }

  @Test("Source text uses UTF-8 offsets")
  func sourceTextUsesUTF8Offsets() throws {
    let file = try FileCollector.collect(
      source: """
      // Café ☕️ before anything else.
      final class Wütend {
        struct Innen {
          let grüße = "héllo 👋"
        }

        func grüßen(mal: Int) -> String {
          "🎉"
        }
      }
      """,
      path: "/virtual/App/Unicode.swift"
    )

    let rendered = file.withSyntax { tree in
      RenderCollector.renderedDeclarations(in: tree)
    }
    let outer = try #require(file.classes.first)
    let inner = try #require(file.structs.first)
    let function = try #require(file.functions.first)
    #expect(rendered["Wütend"] == outer.sourceText)
    #expect(rendered["Innen"] == inner.sourceText)
    #expect(rendered["grüßen"] == function.sourceText)
  }

  @Test("Declarations share their file's source buffer")
  func declarationsShareSourceStorage() throws {
    let file = try FileCollector.collect(
      source: "struct Store { func load() {} }",
      path: "/virtual/App/Store.swift"
    )
    let store = try #require(file.structs.first)
    let load = try #require(file.functions.first)

    #expect(file.source === store.storage.source)
    #expect(file.source === load.source)
    #expect(file.memberStorage === store.storage.memberStorage)
  }

  @Test("Declaration identity uses its source position")
  func declarationIdentityUsesSourcePosition() throws {
    let source = "func load() {}\nfunc load() {}"
    let firstFile = try FileCollector.collect(
      source: source,
      path: "/virtual/App/Store.swift"
    )
    let secondFile = try FileCollector.collect(
      source: source,
      path: "/virtual/App/Store.swift"
    )

    #expect(firstFile.functions[0] == secondFile.functions[0])
    #expect(firstFile.functions[0] != firstFile.functions[1])
    #expect(Set(firstFile.functions).count == 2)
  }

  @Test("Documentation parsing returns parameter names and the return line")
  func extractsDocumentationParts() throws {
    let file = try FileCollector.collect(
      source: """
      /// Adds the numbers.
      ///
      /// - Parameters:
      ///   - a: The first number.
      ///   - b: The second number.
      /// - Returns: The sum.
      func add(_ a: Int, _ b: Int) -> Int { a + b }

      /// Greets someone.
      ///
      /// - Parameter name: Who to greet.
      func greet(_ name: String) {}

      /// Undocumented parameters.
      func undocumentedParameter(_ x: Int) {}
      """,
      path: "/virtual/App/Docs.swift"
    )

    let add = try #require(file.functions.first { $0.name == "add" })
    #expect(add.documentedParameterNames == ["a", "b"])
    #expect(add.documentsReturnValue)

    let greet = try #require(file.functions.first { $0.name == "greet" })
    #expect(greet.documentedParameterNames == ["name"])
    #expect(!greet.documentsReturnValue)

    let undocumentedParameter = try #require(
      file.functions.first { $0.name == "undocumentedParameter" }
    )
    #expect(undocumentedParameter.documentedParameterNames.isEmpty)
  }
}

private final class RenderCollector: SyntaxVisitor {
  private var rendered: [String: String] = [:]

  static func renderedDeclarations(in tree: SourceFileSyntax)
    -> [String: String]
  {
    let collector = RenderCollector(viewMode: .sourceAccurate)
    collector.walk(tree)
    return collector.rendered
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    rendered[node.name.text] = node.trimmedDescription
    return .visitChildren
  }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    rendered[node.name.text] = node.trimmedDescription
    return .visitChildren
  }

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    rendered[node.name.text] = node.trimmedDescription
    return .visitChildren
  }
}
