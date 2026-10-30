import BylawsSyntax
import Testing
@testable import BylawsSemantics

// swiftformat:disable redundantAsync -- Async tests expose stack exhaustion on worker threads.
@Suite("Deeply nested layouts")
struct SourceLayoutDepthTests {
  @Test("Identity layouts preserve deeply nested source", arguments: [64, 128])
  @concurrent
  func identity(depth: Int) async throws {
    let source = expression(depth: depth, leaf: "leaf(1, 2)")
    let file = try parsedFile(depth: depth)
    let edits = try layouts(in: file, depth: depth, leafWidth: 1_000_000)

    let result = try file.source.replacement(applying: edits)

    #expect(result.replacement.utf8.elementsEqual(source.utf8))
  }

  @Test(
    "Active leaf layout survives deeply nested identity ancestors",
    arguments: [64, 128]
  )
  @concurrent
  func activeLeaf(depth: Int) async throws {
    let file = try parsedFile(depth: depth)
    let edits = try layouts(in: file, depth: depth, leafWidth: 1)
    let expected = expression(depth: depth, leaf: "leaf(\n  1,\n  2\n)")

    let result = try file.source.replacement(applying: edits)

    #expect(result.replacement == expected)
  }

  private func expression(depth: Int, leaf: String) -> String {
    "let r = " + String(repeating: "outer(", count: depth - 1) + leaf
      + String(repeating: ", 3)", count: depth - 1) + ".longSuffix"
  }

  private func parsedFile(depth: Int) throws -> SourceFile {
    let leaf = Parser.parse(source: "leaf(1, 2)")
    var nested = try #require(
      leaf.statements.first?.item.as(FunctionCallExprSyntax.self)
    )
    let outer = Parser.parse(source: "outer(0, 3)")
    let template = try #require(
      outer.statements.first?.item.as(FunctionCallExprSyntax.self)
    )
    for _ in 1..<depth {
      var wrapper = template
      let firstIndex = wrapper.arguments.startIndex
      var first = wrapper.arguments[firstIndex]
      first.expression = ExprSyntax(nested)
      wrapper.arguments[firstIndex] = first
      nested = wrapper
    }

    var tree = Parser.parse(source: "let r = placeholder.longSuffix")
    let statementIndex = tree.statements.startIndex
    var statement = tree.statements[statementIndex]
    var declaration = try #require(statement.item.as(VariableDeclSyntax.self))
    let bindingIndex = declaration.bindings.startIndex
    var binding = declaration.bindings[bindingIndex]
    var initializer = try #require(binding.initializer)
    var suffix = try #require(initializer.value.as(MemberAccessExprSyntax.self))
    nested.leadingTrivia = suffix.leadingTrivia
    suffix.base = ExprSyntax(nested)
    initializer.value = ExprSyntax(suffix)
    binding.initializer = initializer
    declaration.bindings[bindingIndex] = binding
    statement.item = .decl(DeclSyntax(declaration))
    tree.statements[statementIndex] = statement

    let source = expression(depth: depth, leaf: "leaf(1, 2)")
    try #require(!tree.hasError)
    try #require(tree.description == source)
    let snapshot = SourceSnapshot(
      filePath: "/Deep.swift", text: source, swiftLanguageMode: .v6
    ).withSyntaxTree(tree)
    return SourceFile(
      path: snapshot.filePath,
      source: SourceBuffer(source, lineCount: 1, snapshot: snapshot)
    )
  }

  private func layouts(
    in file: SourceFile, depth: Int, leafWidth: Int
  ) throws -> [SourceFix.Edit] {
    let calls = file.syntaxNodes(of: .functionCall).compactMap(\.call)
    try #require(calls.count == depth)
    return try calls.map { call in
      if call.name == "leaf" {
        try call.arguments.replacement(whenLineExceeds: leafWidth) {
          for argument in call.arguments {
            Newline()
            argument
          }
          Newline()
        }
      } else {
        try call.arguments.replacement { call.arguments }
      }
    }
  }
}
