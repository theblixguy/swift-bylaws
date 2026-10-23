import BylawsSemantics
import Testing

@Suite("Source node call projections")
struct SourceNodeCallProjectionTests {
  @Test(
    "Call projections preserve arguments through expression wrappers",
    arguments: [
      "send(value: 1)",
      "await send(value: 1)",
      "try send(value: 1)",
      "try? send(value: 1)",
      "try! send(value: 1)",
      "try await send(value: 1)",
      "try? await send(value: 1)",
      "try! await send(value: 1)",
      "(send(value: 1))",
      "((try await send(value: 1)))",
      "await (send(value: 1))",
    ]
  )
  func wrappedCalls(_ statement: String) throws {
    let file = try collect("func work() async throws { \(statement) }")
    let block = try #require(file.syntaxNodes(of: .codeBlock).first)
    let node = try #require(block.statements.first)
    let call = try #require(node.call)
    let argument = try #require(call.arguments.first)

    #expect(call.calledExpression == "send")
    #expect(call.argumentLabels == ["value"])
    #expect(argument.text == "1")
    #expect(try call.source.text == "send(value: 1)")
    #expect(try argument.expressionSource.text == "1")
    #expect(try call.source.filePath == "/virtual/Current/Calls.swift")
    #expect(try call.location.utf8Offset == call.source.range.lowerBound)
    #expect(try call.source == file.calls.first?.source)
  }

  @Test(
    "Call projections exclude calls nested in other statements and expressions",
    arguments: [
      "let value = send()",
      "return send()",
      "throw makeError()",
      "if ready { send() }",
      "{ send() }",
      "[send()]",
      "(send(), other())",
      "(value: send())",
      "(send(),)",
      "try await send() + other()",
      "send().value",
      "send()[0]",
      "send()!",
      "send() as Value",
    ]
  )
  func nestedCalls(_ statement: String) throws {
    let file = try collect("func work() async throws { \(statement) }")
    let block = try #require(file.syntaxNodes(of: .codeBlock).first)
    let node = try #require(block.statements.first)

    #expect(node.call == nil)
    #expect(node.contains(.functionCall))
  }

  @Test("Outermost call retains nested call arguments")
  func outerCall() throws {
    let file = try collect("func work() { send(value: makeValue()) }")
    let block = try #require(file.syntaxNodes(of: .codeBlock).first)
    let node = try #require(block.statements.first)
    let call = try #require(node.call)

    #expect(call.calledExpression == "send")
    #expect(call.arguments.first?.text == "makeValue()")
  }

  @Test("Macro call projections retain names and arguments", arguments: [
    "#publish(value: 1)",
    "try await #publish(value: 1)",
    "(#publish(value: 1))",
  ])
  func macroCalls(_ statement: String) throws {
    let file = try collect("func work() async throws { \(statement) }")
    let block = try #require(file.syntaxNodes(of: .codeBlock).first)
    let node = try #require(block.statements.first)
    let call = try #require(node.call)

    #expect(call.calledExpression == "#publish")
    #expect(call.argumentLabels == ["value"])
    #expect(try call.source.text == "#publish(value: 1)")
  }

  @Test("Member macro call projections retain captured source")
  func memberMacro() throws {
    let file = try collect("struct Store { #members(value: 1) }")
    let declaration = try #require(file.syntaxNodes(of: .structDeclaration)
      .first)
    let member = try #require(declaration.members.first)
    let call = try #require(member.call)

    #expect(call.calledExpression == "#members")
    #expect(call.argumentLabels == ["value"])
    #expect(try call.source.text == "#members(value: 1)")
  }

  @Test("Call edits preserve wrappers, comments and surrounding Unicode")
  func sourceEdits() throws {
    let source = """
    func work() async throws {
      let café = 0
      try await (/* Keep. */ store.send(value: café))
    }
    """
    let file = try collect(source)
    let block = try #require(file.syntaxNodes(of: .codeBlock).first)
    let node = try #require(block.statements.last)
    let call = try #require(node.call)
    let edit = try call.memberNameSource.replacement(with: "save")
    let replacement = try file.source.replacement(applying: [edit])

    #expect(call.location.line == 3)
    #expect(try call.source.text == "store.send(value: café)")
    #expect(replacement.replacement == """
    func work() async throws {
      let café = 0
      try await (/* Keep. */ store.save(value: café))
    }
    """)
  }

  private func collect(_ source: String) throws -> SourceFile {
    try FileCollector.collect(
      source: source,
      path: "/virtual/Current/Calls.swift"
    )
  }
}
