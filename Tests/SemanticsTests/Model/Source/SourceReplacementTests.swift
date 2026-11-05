import BylawsSemantics
import Foundation
import Testing

@Suite("Captured syntax replacements")
struct SourceReplacementTests {
  @Test("Retained argument keeps grouping and nested corrections")
  func expressionGrouping() throws {
    let file = try collect("let result = identity(left + right) * scale")
    let call = try #require(file.calls.first)
    let argument = try #require(call.arguments.first)
    let replacement = try Replace(call, with: argument)
    let fix = try #require(replacement.correction.fix)
    let right = try #require(file.syntaxNodes(of: .identifierReference)
      .first { $0.text == "right" })
    let edit = try right.source.replacement(with: "other")

    #expect(try file.source.replacement(applying: fix.edits + [edit])
      .replacement
      == "let result = (left + other) * scale")
  }

  @Test("Nested replacement can introduce expression grouping")
  func changedExpressionGrouping() throws {
    let file = try collect("let result = identity(value) * scale")
    let call = try #require(file.calls.first)
    let argument = try #require(call.arguments.first)
    let replacement = try call.source.replacement(with: argument)
    let nested = try argument.expressionSource.replacement(with: "left + right")

    #expect(try file.source.replacement(applying: [replacement, nested])
      .replacement
      == "let result = (left + right) * scale")
  }

  @Test("Nested expression replacement rejects extra statements")
  func extraExpressionContent() throws {
    let file = try collect("let result = identity(value)")
    let call = try #require(file.calls.first)
    let argument = try #require(call.arguments.first)
    let replacement = try call.source.replacement(with: argument)
    let nested = try argument.expressionSource
      .replacement(with: "first; second")

    #expect(throws: SourceReplacementError.syntaxChanged) {
      try file.source.replacement(applying: [replacement, nested])
    }
  }

  @Test("Function body replacement retains required braces")
  func requiredBody() throws {
    let file = try collect("func run() { work() }")
    let body = try #require(file.syntaxNodes(of: .codeBlock).first)
    let statement = try #require(body.statements.first)
    let result = try Replace(body, with: statement).correction

    #expect(result.outcome == .violation)
    #expect(result.fix == nil)
  }

  @Test("Retained optional chain keeps its original boundary", arguments: [
    "item?.value", "item?.value!.name", "item?.method<Int>()",
  ])
  func optionalChain(_ expression: String) throws {
    let file = try collect("let text = identity(\(expression)).description")
    let call = try #require(file.calls.first)
    let argument = try #require(call.arguments.first)
    let edit = try call.source.replacement(with: argument)

    #expect(try file.source.replacement(applying: [edit]).replacement
      == "let text = (\(expression)).description")
  }

  @Test("Retained descendant composes with its layout")
  func nestedLayout() throws {
    let file = try collect("let result = identity(send(first: 1, second: 2))")
    let wrapper = try #require(file.calls.first { $0.name == "identity" })
    let call = try #require(file.calls.first { $0.name == "send" })
    let replacement = try wrapper.source.replacement(with: call)
    let layout = try call.arguments.replacement {
      for argument in call.arguments {
        Newline()
        argument
      }
      Newline()
    }

    #expect(try file.source.replacement(applying: [replacement, layout])
      .replacement
      == "let result = send(\n  first: 1,\n  second: 2\n)")
  }

  @Test("Scope replacement keeps statements and defer inside a block")
  func scope() throws {
    let file = try collect("""
    func run() {
      if enabled {
        defer { finish() }
        work()
      } else {
        fallback()
      }
      continueWork()
    }
    """)
    let node = try #require(file.syntaxNodes(of: .ifExpression).first)
    let condition = try #require(node.ifExpression)
    let replacement = try Replace(node) {
      try Scope { try condition.body.statementList }
    }
    let fix = try #require(replacement.correction.fix)

    #expect(try file.source.replacement(applying: fix.edits).replacement == """
    func run() {
      do {
        defer { finish() }
        work()
      }
      continueWork()
    }
    """)
  }

  @Test("Expression replacement cannot create extra statements")
  func expressionBoundary() throws {
    let file = try collect("let value = combine(first, second)")
    let call = try #require(file.calls.first)
    let correction = try Replace(call) {
      try call.arguments.map { try $0.expressionSource }
    }.correction

    #expect(correction.outcome == .violation)
    #expect(correction.fix == nil)
  }

  @Test("Corrections in discarded code conflict")
  func discardedEdits() throws {
    let file = try collect("let result = identity(value)")
    let call = try #require(file.calls.first)
    let argument = try #require(call.arguments.first)
    let replacement = try call.source.replacement(with: argument)
    let renamed = try call.calledExpressionSource.replacement(with: "other")

    #expect(throws: SourceError.overlappingEdits) {
      try file.source.replacement(applying: [replacement, renamed])
    }
  }

  @Test(
    "Captured replacement survives coding and retains nested edit ownership"
  )
  func coding() throws {
    let file = try collect("let value = identity(1)")
    let call = try #require(file.calls.first)
    let argument = try #require(call.arguments.first)
    let original = try call.source.replacement(with: argument)
    let decoded = try JSONDecoder().decode(
      SourceFix.Edit.self, from: JSONEncoder().encode(original)
    )
    let nested = try argument.source.replacement(with: "2")

    #expect(try file.source.replacement(applying: [decoded, nested]).replacement
      == "let value = 2")
  }

  @Test("Structural correction decoding rejects a changed preview")
  func changedPreview() throws {
    let file = try collect("let value = identity(1)")
    let call = try #require(file.calls.first)
    let argument = try #require(call.arguments.first)
    let original = try call.source.replacement(with: argument)
    var payload = try #require(JSONSerialization.jsonObject(
      with: JSONEncoder().encode(original)
    ) as? [String: Any])
    payload["replacement"] = "other()"
    let encoded = try JSONSerialization.data(withJSONObject: payload)

    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(SourceFix.Edit.self, from: encoded)
    }
  }

  @Test("Decoded replacement cannot remove required grouping")
  func changedGrouping() throws {
    let file = try collect("let value = identity(left + right) * scale")
    let call = try #require(file.calls.first)
    let argument = try #require(call.arguments.first)
    let original = try call.source.replacement(with: argument)
    var payload = try #require(JSONSerialization.jsonObject(
      with: JSONEncoder().encode(original)
    ) as? [String: Any])
    var layout = try #require(payload["layout"] as? [String: Any])
    var mode = try #require(layout["mode"] as? [String: Any])
    var payloadValue = try #require(mode["replacement"] as? [String: Any])
    var replacement = try #require(payloadValue["_0"] as? [String: Any])
    let node = try #require(replacement["node"] as? [String: Any])
    let parentheses = try #require(node["parentheses"] as? [String: Any])
    replacement["node"] = try #require(parentheses["_0"] as? [String: Any])
    payloadValue["_0"] = replacement
    mode["replacement"] = payloadValue
    layout["mode"] = mode
    payload["layout"] = layout
    payload["replacement"] = "left + right"
    let encoded = try JSONSerialization.data(withJSONObject: payload)

    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(SourceFix.Edit.self, from: encoded)
    }
  }

  @Test(
    "Structural payload rejects unknown and multiple modes",
    arguments: [false, true]
  )
  func unknownMode(multiple: Bool) throws {
    let file = try collect("let value = identity(1)")
    let call = try #require(file.calls.first)
    let original = try call.source
      .replacement(with: #require(call.arguments.first))
    var payload = try #require(JSONSerialization
      .jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
    var layout = try #require(payload["layout"] as? [String: Any])
    var mode = multiple ? try #require(layout["mode"] as? [String: Any]) : [:]
    mode[multiple ? "listMutation" : "unknown"] = [String: String]()
    layout["mode"] = mode
    payload["layout"] = layout
    let encoded = try JSONSerialization.data(withJSONObject: payload)

    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(SourceFix.Edit.self, from: encoded)
    }
  }

  @Test("Replacement preserves comments inside retained source")
  func retainedComments() throws {
    let file = try collect("let result = identity(send(/* Keep. */ value))")
    let wrapper = try #require(file.calls.first { $0.name == "identity" })
    let call = try #require(file.calls.first { $0.name == "send" })
    let edit = try wrapper.source.replacement(with: call)

    #expect(try file.source.replacement(applying: [edit]).replacement
      == "let result = send(/* Keep. */ value)")
  }

  @Test("Multiline literal replacement remains unavailable")
  func multilineLiteral() throws {
    let file = try collect(#"""
    let value = identity("""
      Keep these bytes.
      """)
    """#)
    let call = try #require(file.calls.first)
    let argument = try #require(call.arguments.first)
    let correction = try Replace(call, with: argument).correction

    #expect(correction.outcome == .violation)
    #expect(correction.fix == nil)
    #expect(correction.reason != nil)
  }

  @Test("Captured replacement rejects foreign snapshots and partial syntax")
  func sourceBoundaries() throws {
    let file = try collect("let value = identity(123)")
    let other = try FileCollector.collect(
      source: "let value = 456",
      path: "/Other.swift"
    )
    let call = try #require(file.calls.first)
    let foreign = try #require(other.syntaxNodes(of: .integerLiteral).first)
    let argument = try #require(call.arguments.first)
    let partial = try argument.source.slice(0..<1)

    #expect(throws: SourceError.differentSnapshots) {
      try call.source.replacement(with: foreign)
    }
    #expect(throws: SourceError.syntaxMismatch) {
      try call.source.replacement(with: partial)
    }
  }

  @Test("Whitespace replacement uses existing source checks")
  func whitespace() throws {
    let file = try collect("let result = send(1, 2)")
    let call = try #require(file.calls.first)
    let argument = try #require(call.arguments.last)
    let replacement = try Replace(argument.spacing.before, with: .newline)
    let fix = try #require(replacement.correction.fix)

    #expect(try file.source.replacement(applying: fix.edits).replacement
      == "let result = send(1,\n2)")
  }

  private func collect(_ source: String) throws -> SourceFile {
    try FileCollector.collect(
      source: source,
      path: "/virtual/Replacement.swift"
    )
  }
}
