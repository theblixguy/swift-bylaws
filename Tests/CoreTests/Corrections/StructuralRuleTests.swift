import Bylaws
import BylawsCore
import Testing

@Suite("Structural correction rules")
struct StructuralRuleTests {
  @Test("Native conditional selection retains nested fixes")
  func elseIf() async throws {
    let codebase = Codebase(root: .sources([
      "Flow.swift": "func run() { if first {} else { if second {} else { if third {} } } }",
    ]))
    let result = try await codebase.ifExpressions
      .violations("Use else if") { conditional in
        try Unwrap(conditional.elseBody, containingOnly: .ifExpression)
      }
    let edits = result.fixes.compactMap(\.self).flatMap(\.edits)
    let file = try #require(edits.first).source.file

    #expect(result.checkedCount == 3)
    #expect(result.offenders.count == 2)
    #expect(try file.replacement(applying: edits).replacement
      == "func run() { if first {} else if second {} else if third {} }")
  }

  @Test("Native replacement values compose with builder operations")
  func values() async throws {
    let codebase = Codebase(root: .sources([
      "Flow.swift": "let total = identity(left + right) * scale",
    ]))
    let result = try await codebase.calls
      .violations("Remove identity") { call in
        let argument = try call.arguments.only()
        let replacement = try SourceReplacement(source: argument
          .expressionSource)
        try Replace(call, with: replacement)
      }
    let edit = try #require(result.fixes.compactMap(\.self).first?.edits.first)

    #expect(try edit.source.file.replacement(applying: [edit]).replacement
      == "let total = (left + right) * scale")
  }

  @Test("Native unknown builder context cannot pass")
  func unknownContext() async {
    let codebase = Codebase(root: .sources([
      "Flow.swift": "var body: some View { if first {} else { if second {} } }",
    ]))

    await #expect(throws: SourceCorrectionError.self) {
      try await codebase.ifExpressions
        .violations("Use else if") { conditional in
          try Unwrap(conditional.elseBody, containingOnly: .ifExpression)
        }
    }
  }
}
