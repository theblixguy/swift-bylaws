import Bylaws
import Testing

@Suite("Source list rule corrections")
struct SourceListRuleTests {
  @Test("Grouping rule infers source elements and correction type")
  func inferredGrouping() async throws {
    let source = "struct Store {\n  var count = 0\n  let limit = 1\n}"
    let app = Codebase(root: .sources(["Sources/Store.swift": source]))
    let violations = try await app.syntaxNodes(of: .structDeclaration)
      .violations("Constants precede variables") { declaration in
        try declaration.members.replacement {
          Group(where: { $0.property?.isConstant == true })
          BlankLine()
          Group(where: { _ in true })
        }
      }
    let fix = try #require(violations.fixes.first ?? nil)
    let edit = try #require(fix.edits.first)
    let corrected = try edit.source.file.replacement(applying: fix.edits)
      .replacement

    #expect(corrected ==
      "struct Store {\n  let limit = 1\n\n  var count = 0\n}")
  }

  @Test("Spacing correction and explicit edits share rule builder")
  func inferredSpacing() async throws {
    let source = "func work() {\n  first()\n  second()\n  third()\n}"
    let app = Codebase(root: .sources(["Sources/Calls.swift": source]))
    let violations = try await app.syntaxNodes(of: .codeBlock)
      .violations("Calls use blank lines and current names") { block in
        let correction = try block.statements.replacement {
          BlankLine(before: { _ in true })
        }
        correction
        if let call = block.statements.last?.call {
          try call.memberNameSource.replacement(with: "finish")
        }
      }
    let fix = try #require(violations.fixes.first ?? nil)
    let edit = try #require(fix.edits.first)
    let corrected = try edit.source.file.replacement(applying: fix.edits)
      .replacement

    #expect(fix.edits.count == 3)
    #expect(corrected ==
      "func work() {\n  first()\n\n  second()\n\n  finish()\n}")
  }
}
