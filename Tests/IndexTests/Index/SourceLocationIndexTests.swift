import BylawsCore
import BylawsIndex
import BylawsIndexStore
import BylawsSemantics
import Testing

@Suite(
  "Compiler occurrence locations",
  .enabled(
    if: IndexUnderTest.isAvailable,
    "Build with an index store to run these tests."
  ),
  .tags(.indexStore)
)
struct SourceLocationIndexTests {
  @Test("Overloads retain distinct identities without matching a local shadow")
  func overloadsAndShadowing() async throws {
    let index = try await IndexUnderTest.testModules.projectIndex(
      modules: IndexUnderTest.testModuleNames
    )
    let file = try #require(await IndexUnderTest.testModules.files
      .named("SourceLocationCalls.swift").first)
    let calls = file.calls.filter { $0.calledExpression == "save" }
    try #require(calls.count == 3)
    let symbols = try calls.prefix(2).map { call in
      let references = index.occurrences(at: call.location).filter {
        $0.roles.contains(.reference) && !$0.roles.contains(.implicit)
      }
      try #require(references.count == 1, "\(call.location): \(references)")
      return try #require(references.first).symbol
    }
    let identifiers = Set(symbols.map(\.usr))
    #expect(identifiers.count == 2)
    #expect(symbols[0].kind == .staticMethod)
    #expect(symbols[1].kind == .staticMethod)
    let shadow = index.occurrences(at: calls[2].location)
    #expect(shadow.allSatisfy { !identifiers.contains($0.symbol.usr) })
  }

  @Test("Compiler reference locations resolve to their recorded identities")
  func references() async throws {
    let index = try await IndexUnderTest.index()
    let references = index.references(to: "IndexSymbol")
    try #require(!references.isEmpty)
    for reference in references {
      #expect(index.occurrences(at: reference.location).contains(reference))
    }
  }

  @Test("Unknown files do not resolve by matching a symbol name")
  func unknownFile() async throws {
    let index = try await IndexUnderTest.index()
    let reference = try #require(index.references(to: "IndexSymbol").first)
    let location = DeclarationLocation(
      filePath: "/virtual/NotIndexed.swift",
      line: reference.line, column: reference.column
    )
    #expect(index.occurrences(at: location).isEmpty)
  }
}
