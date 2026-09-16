import BylawsSemantics
import Testing
@testable import BylawsCore

@Suite("Selection cache with deferred inheritance")
struct SelectionInheritanceIntegrationTests {
  @Test("Repeated raw and resolved queries keep separate cached results")
  func separateResults() async throws {
    let app = Codebase(root: .sources([
      "Models.swift": """
      protocol Named {}
      class Base {}
      class Parent: Base {}
      class Child: Parent {}
      extension Parent: Named {}
      """,
    ]))
    let cache = SelectionCacheStore(maximumBytes: 1_000_000)
    for _ in 0..<3 {
      for mode in [ParsedCodebase.Declarations.asWritten, .resolved] {
        let source = try await app.usingDeclarations(mode).classes
        let selection = try await cache.selection(
          from: source,
          filters: [.named(["Child"])]
        )
        let child = try #require(selection.first)
        #expect(child.inherits(from: "Base") == (mode == .resolved))
        #expect(child.conforms(to: "Named") == (mode == .resolved))
      }
    }
    await cache.finish()
    #expect(await cache.retainedBytes == 0)
  }
}
