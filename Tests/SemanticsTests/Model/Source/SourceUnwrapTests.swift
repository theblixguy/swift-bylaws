import BylawsSemantics
import Testing

@Suite("Source wrapper corrections")
struct SourceUnwrapTests {
  @Test("Else-if corrections retain nested edits and adjust indentation")
  func nestedConditions() throws {
    let file = try collect("""
    func choose() -> Int {
      if first {
        return 1
      } else {
        if second {
          return 2
        } else {
          if third {
            return 3
          } else {
            return 4
          }
        }
      }
    }
    """)
    let edits = try file.syntaxNodes(of: .ifExpression).flatMap { node in
      try Unwrap(node.ifExpression?.elseBody, containingOnly: .ifExpression)
        .correction.fix?.edits ?? []
    }
    let result = try file.source.replacement(applying: edits)

    #expect(edits.count == 2)
    #expect(result.replacement == """
    func choose() -> Int {
      if first {
        return 1
      } else if second {
        return 2
      } else if third {
        return 3
      } else {
        return 4
      }
    }
    """)
  }

  @Test("Else branch with another statement does not match")
  func additionalStatement() throws {
    let file =
      try collect("func run() { if ready {} else { log(); if other {} } }")
    let alternative = try #require(file.syntaxNodes(of: .ifExpression).first?
      .ifExpression?.elseBody)
    let result = try Unwrap(alternative, containingOnly: .ifExpression)
      .correction

    #expect(result.outcome == .notApplicable)
    #expect(result.fix == nil)
  }

  @Test("Unknown builder context remains undetermined", arguments: [
    "var body: some View { if ready { first() } else { if other { second() } } }",
    "func run() { build { if ready { first() } else { if other { second() } } } }",
    "var body: some View { let action = { return 1 }; if ready { first() } else { if other { second() } } }",
    "let value = if ready { 1 } else { if other { 2 } else { 3 } }",
    """
    var body: some View {
      #if NEVER
      return EmptyView()
      #endif
      if ready { first() } else { if other { second() } }
    }
    """,
  ])
  func unknownContext(_ source: String) throws {
    let file = try collect(source)
    let alternative = try #require(file.syntaxNodes(of: .ifExpression).first?
      .ifExpression?.elseBody)
    let result = try Unwrap(alternative, containingOnly: .ifExpression)
      .correction

    #expect(result.outcome == .undetermined)
    #expect(result.reason != nil)
    #expect(result.fix == nil)
  }

  @Test("Owning closure return establishes ordinary control flow")
  func explicitClosureReturn() throws {
    let file =
      try collect(
        "let value = { if ready { return 1 } else { if other { return 2 } else { return 3 } } }()"
      )
    let alternative = try #require(file.syntaxNodes(of: .ifExpression).first?
      .ifExpression?.elseBody)
    let result = try Unwrap(alternative, containingOnly: .ifExpression)
      .correction
    let fix = try #require(result.fix)

    #expect(try file.source.replacement(applying: fix.edits).replacement
      ==
      "let value = { if ready { return 1 } else if other { return 2 } else { return 3 } }()")
  }

  @Test("Discarded brace comments retain a violation without a correction")
  func discardedComment() throws {
    let file =
      try collect("func run() { if ready {} else { /* Keep. */ if other {} } }")
    let alternative = try #require(file.syntaxNodes(of: .ifExpression).first?
      .ifExpression?.elseBody)
    let result = try Unwrap(alternative, containingOnly: .ifExpression)
      .correction

    #expect(result.outcome == .violation)
    #expect(result.reason != nil)
    #expect(result.fix == nil)
  }

  @Test("Parenthesis corrections preserve expression grouping", arguments: [
    ("let value = (item)", "let value = item"),
    ("let value = ((left + right))", "let value = (left + right)"),
    (
      "let value = (left + right) * scale",
      "let value = (left + right) * scale"
    ),
    ("let value = (first, second)", "let value = (first, second)"),
    (
      "if (items.contains { $0.ready }) { accept() }",
      "if (items.contains { $0.ready }) { accept() }"
    ),
  ])
  func parentheses(source: String, expected: String) throws {
    let file = try collect(source)
    let tuple = try #require(file.syntaxNodes(of: .tupleExpression).first)
    let correction = try Unwrap(tuple).correction
    let result = try file.source
      .replacement(applying: correction.fix?.edits ?? [])

    #expect(result.replacement == expected)
  }

  @Test("Type parentheses retain function and optional boundaries", arguments: [
    ("typealias Value = (Int)", "(Int)", "typealias Value = Int"),
    ("var callback: (() -> Int)?", "(() -> Int)", "var callback: (() -> Int)?"),
    ("var value: (any Item)?", "(any Item)", "var value: (any Item)?"),
  ])
  func typeParentheses(
    source: String,
    target: String,
    expected: String
  ) throws {
    let file = try collect(source)
    let slice = try #require(file.source
      .matches(of: Regex<Substring>(verbatim: target))
      .first)
    let correction = try slice.unwrapped()

    #expect(try file.source.replacement(applying: correction.fix?.edits ?? [])
      .replacement == expected)
  }

  @Test("Return unwrapping preserves type uncertainty", arguments: [
    "func value() -> Int { return 1 }",
    "func value() -> Int { return fatalError() }",
    "typealias Result = Void; func value() -> Result { return work() }",
  ])
  func implicitReturn(_ source: String) throws {
    let file = try collect(source)
    let statement = try #require(file.syntaxNodes(of: .returnStatement).first)
    let result = try statement.unwrapped()

    #expect(result.outcome == .undetermined)
    #expect(result.fix == nil)
  }

  @Test("Scope and closure effects remain undetermined", arguments: [
    (
      "do { defer { finish() }; work() }; continueWork()",
      SourceNode.Kind.doStatement
    ),
    ("let value = { () -> Double in 1 }()", .functionCall),
    ("let value = identity(1)", .functionCall),
    ("let work = { [owner] in owner.run() }", .closureExpression),
    ("var body: some View { return content }", .returnStatement),
  ])
  func unsupportedScope(source: String, kind: SourceNode.Kind) throws {
    let file = try collect(source)
    let node = try #require(file.syntaxNodes(of: kind).first)
    let correction = try node.unwrapped()

    #expect(correction.outcome == .undetermined)
    #expect(correction.fix == nil)
  }

  @Test("Unsupported scope filters match sole direct content", arguments: [
    (
      "do { first(); second() }",
      SourceNode.Kind.doStatement,
      SourceCorrection.Outcome.notApplicable
    ),
    ("let work = { first(); second() }", .closureExpression, .notApplicable),
    ("let result = { first(); second() }()", .functionCall, .notApplicable),
    ("do { if ready {} }", .doStatement, .notApplicable),
    ("let work = { if ready {} }", .closureExpression, .notApplicable),
    ("let result = { if ready {} }()", .functionCall, .notApplicable),
    ("do { work() }", .doStatement, .undetermined),
    ("let work = { work() }", .closureExpression, .undetermined),
    ("let result = { work() }()", .functionCall, .undetermined),
  ])
  func scopeFilter(
    source: String,
    kind: SourceNode.Kind,
    outcome: SourceCorrection.Outcome
  ) throws {
    let file = try collect(source)
    let node = try #require(file.syntaxNodes(of: kind).first)
    let correction = try node.unwrapped(containingOnly: .functionCall)

    #expect(correction.outcome == outcome)
    #expect(correction.fix == nil)
  }

  private func collect(_ source: String) throws -> SourceFile {
    try FileCollector.collect(source: source, path: "/virtual/Unwrap.swift")
  }
}
