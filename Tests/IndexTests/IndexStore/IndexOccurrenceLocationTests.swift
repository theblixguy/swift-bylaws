import Testing
@testable import BylawsIndexStore

@Suite("Indexed source positions")
struct IndexOccurrenceLocationTests {
  @Test("Exact positions preserve all symbols and roles")
  func exactPositions() {
    let first = reference(usr: "first", line: 2, column: 8)
    let second = reference(usr: "second", line: 2, column: 8)
    let later = reference(usr: "first", line: 2, column: 9)
    let other = reference(
      usr: "first",
      file: "/virtual/Other.swift",
      line: 2,
      column: 8
    )
    let storage = IndexOccurrences([later, other, second, first])
    #expect(storage.at(file: first.file, line: 2, column: 8) == [first, second])
    #expect(storage.at(file: first.file, line: 2, column: 9) == [later])
    #expect(storage.at(file: other.file, line: 2, column: 8) == [other])
    #expect(storage.matching(["first"]) == [first, later, other])
    #expect(storage.matching(["missing"]).isEmpty)
    #expect(Array(storage.groups) == [[first, later, other], [second]])
  }

  @Test("Unknown positions return no nearby occurrence")
  func missingPositions() {
    let storage = IndexOccurrences([reference(
      usr: "symbol",
      line: 2,
      column: 8
    )])
    #expect(storage.at(file: "/virtual/File.swift", line: 2, column: 7).isEmpty)
    #expect(storage.at(file: "/virtual/File.swift", line: 2, column: 9).isEmpty)
    #expect(storage.at(file: "/virtual/File.swift", line: 1, column: 8).isEmpty)
    #expect(storage.at(file: "/virtual/Other.swift", line: 2, column: 8)
      .isEmpty)
    #expect(storage.at(file: "/virtual/File.swift", line: 0, column: 0).isEmpty)
    #expect(IndexOccurrences([]).at(
      file: "/virtual/File.swift",
      line: 1,
      column: 1
    ).isEmpty)
  }

  @Test("Occurrences with different roles remain distinct at one position")
  func distinctRoles() {
    let call = reference(usr: "symbol", line: 2, column: 8)
    let implicit = IndexReference(
      symbol: call.symbol, module: call.module, file: call.file,
      line: call.line, column: call.column, roles: [.reference, .implicit]
    )
    let storage = IndexOccurrences([implicit, call])
    let matches = storage.at(
      file: call.file,
      line: call.line,
      column: call.column
    )
    #expect(matches.count == 2)
    #expect(Set(matches) == [call, implicit])
  }

  @Test("Same-named symbols retain separate compiler identities")
  func distinctSymbols() {
    let first = reference(usr: "moduleA.symbol", line: 1, column: 5)
    let second = reference(usr: "moduleB.symbol", line: 1, column: 5)
    let storage = IndexOccurrences([second, first])
    #expect(storage.matching([first.symbol.usr]) == [first])
    #expect(storage.matching([second.symbol.usr]) == [second])
    #expect(storage.at(file: first.file, line: 1, column: 5)
      .map(\.symbol.usr) == [
        "moduleA.symbol",
        "moduleB.symbol",
      ])
  }

  private func reference(
    usr: String, file: String = "/virtual/File.swift", line: Int, column: Int
  ) -> IndexReference {
    IndexReference(
      symbol: IndexSymbol(usr: usr, name: "symbol", kind: .function),
      module: "App", file: file, line: line, column: column,
      roles: [.reference, .call]
    )
  }
}
