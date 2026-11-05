import Bylaws
import Testing

@Suite("Source list rule builders")
struct SourceListBuilderTests {
  @Test("Declaration insertions share a fix and rerun cleanly")
  func declarationPolicy() async throws {
    let original = "class Store {}"
    let app = Codebase(root: .sources(["Store.swift": original]))
    let violations = try await check(app)
    let fix = try #require(violations.fixes.first ?? nil)
    let file = try #require(fix.edits.first).source.file
    let corrected = try file.replacement(applying: fix.edits).replacement

    #expect(corrected == "@MainActor final class Store {}")
    let rerun =
      try await check(Codebase(root: .sources(["Store.swift": corrected])))
    #expect(rerun.isEmpty)
  }

  private func check(_ app: Codebase) async throws -> Violations<Class> {
    try await app.classes.violations("Isolate final stores") { declaration in
      if !declaration.hasAttribute("MainActor") {
        try Insert("@MainActor", into: declaration.attributeList)
      }
      if !declaration.isFinal {
        try Insert("final", into: declaration.modifierList)
      }
    }
  }
}
