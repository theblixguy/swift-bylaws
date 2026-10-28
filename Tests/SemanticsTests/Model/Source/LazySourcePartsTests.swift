import BylawsSyntax
import Foundation
import Testing
@testable import BylawsSemantics

@Suite("Lazy source parts")
struct LazySourcePartsTests {
  @Test("Argument labels remain outside repeated Unicode expressions")
  func argumentSpans() throws {
    let file = try FileCollector.collect(
      source: "let value = send(label: \"🦊\", \"🦊\")",
      path: "/virtual/Arguments.swift"
    )
    let call = try #require(file.calls.first)
    try #require(call.arguments.count == 2)
    let first = call.arguments[0]
    let second = call.arguments[1]
    let firstExpression = try first.expressionSource
    #expect(firstExpression.snapshot.parsedTree == nil)

    #expect(try first.labelSource?.text == "label")
    #expect(try first.labelSource?.range == 17..<22)
    #expect(firstExpression.range == 24..<30)
    #expect(firstExpression.text == "\"🦊\"")
    #expect(try second.expressionSource.range == 32..<38)
    #expect(try second.expressionSource.text == "\"🦊\"")
    #expect(try second.labelSource == nil)
    #expect(try call.calledExpressionSource.range == 12..<16)
    #expect(try call.memberNameSource.text == "send")
  }

  @Test("Macro projections retain callee and identifier spans")
  func macroSpans() throws {
    let file = try FileCollector.collect(
      source: "#inspect(value: 1)", path: "/virtual/Macros.swift"
    )
    let macro = try #require(file.macroExpansions.first)
    let whole = try macro.source
    #expect(whole.snapshot.parsedTree == nil)

    #expect(whole.text == "#inspect(value: 1)")
    #expect(try macro.nameSource.text == "#inspect")
    #expect(try macro.nameSource.range == 0..<8)
    #expect(try macro.calledExpressionSource.range == 0..<8)
    #expect(try macro.memberNameSource.text == "inspect")
    #expect(try macro.memberNameSource.range == 1..<8)
  }

  @Test("Public model transport leaves lazy source unavailable")
  func publicDecoding() throws {
    let file = try FileCollector.collect(
      source: "let value = send(label: 1)", path: "/virtual/Arguments.swift"
    )
    let call = try #require(file.calls.first)
    let encoded = try JSONEncoder().encode(call)
    let decoded = try JSONDecoder().decode(FunctionCall.self, from: encoded)
    let argument = try #require(decoded.arguments.first)
    #expect(!file.sourceBuffer.hasLoadedSnapshot)

    #expect(throws: SourceError.unavailable) { _ = try decoded.nameSource }
    #expect(throws: SourceError.unavailable) { _ = try argument.labelSource }
    let synthetic = FunctionCall(
      calledExpression: "send", location: .start(of: "/virtual/Arguments.swift")
    )
    #expect(throws: SourceError.unavailable) {
      _ = try synthetic.calledExpressionSource
    }
  }

  @Test(
    "Fragment provenance rejects changed text, path and offset",
    arguments: [
      ("8", "/virtual/Arguments.swift", 17),
      ("7", "/virtual/Other.swift", 17),
      ("7", "/virtual/Arguments.swift", 18),
    ]
  )
  func fragmentAuthority(text: String, filePath: String, offset: Int) throws {
    let file = try FileCollector.collect(
      source: "let value = send(7)\n", path: "/virtual/Arguments.swift"
    )
    let argument = try #require(file.calls.first?.arguments.first)
    let provenance = try #require(argument.parsedSource)
    let expression = try #require(
      SourceExpression.parse(
        text,
        at: DeclarationLocation(
          filePath: filePath, line: 1, column: offset + 1, utf8Offset: offset
        ),
        swiftLanguageMode: .v6,
        capturedSource: provenance
      )
    )

    #expect(!file.sourceBuffer.hasLoadedSnapshot)
    #expect(throws: SourceError.unavailable) { _ = try expression.source }
  }

  @Test("Compound RHS shares captured file and retains trivia")
  func compoundSource() throws {
    let file = try FileCollector.collect(
      source: "func run() { target = first /* keep */ + second }\n",
      path: "/virtual/Assignment.swift"
    )
    let assignment = try #require(file.assignments.first)
    let snapshot = try #require(file.sourceBuffer.snapshot)
    let tree = try #require(snapshot.parsedTree)
    let right = try assignment.value.source

    #expect(assignment.value.sourceTextContext.capturedBuffer === file
      .sourceBuffer)
    #expect(right.text == "first /* keep */ + second")
    #expect(right.range == 22..<47)
    #expect(right.snapshot.parsedTree?.id == tree.id)
    #expect(right.file
      .text == "func run() { target = first /* keep */ + second }\n")
  }

  @Test("Synthetic compound RHS retains no source authority")
  func syntheticCompound() throws {
    let expression = try #require(
      SourceExpression.parse(
        "target = first + second", at: .start(of: "/virtual/Assignment.swift"),
        swiftLanguageMode: .v6
      )
    )
    let assignment = try #require(SourceAssignment(expression))

    #expect(assignment.value.text == "first + second")
    #expect(throws: SourceError.unavailable) { _ = try assignment.source }
    #expect(throws: SourceError.unavailable) { _ = try assignment.value.source }
  }
}
