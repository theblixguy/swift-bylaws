import BylawsSemantics
import Testing

@Suite("Attribute predicates")
struct AttributePredicateTests {
  @Test("Throwing predicates read captured argument source")
  func sourcePredicate() throws {
    let declaration =
      try declaration("@Label(\"first\") @Label(\"second\") class Store {}")
    let matches = try declaration.hasAttribute("Label", argument: { argument in
      try argument.source.text == "\"second\""
    })
    #expect(matches)
  }

  @Test("Predicate source failures retain error type")
  func sourceFailure() throws {
    let declaration = try declaration("@Label(\"first\") class Store {}")
    #expect(throws: SourceError.rangeOutOfBounds) {
      try declaration.hasAttribute("Label", argument: { argument in
        try argument.source.slice(999..<1000).text.isEmpty
      })
    }
  }

  @Test("Matching attribute stops later predicate calls")
  func shortCircuit() throws {
    let declaration =
      try declaration("@Label(\"first\") @Label(\"second\") class Store {}")
    var checked: [String] = []
    let matches = try declaration.hasAttribute("Label", argument: { argument in
      checked.append(argument.text)
      if argument.stringValue == "first" { return true }
      return try argument.source.slice(999..<1000).text.isEmpty
    })
    #expect(matches)
    #expect(checked == ["\"first\""])
  }

  private func declaration(_ source: String) throws -> Class {
    let file = try FileCollector.collect(
      source: source,
      path: "/virtual/Attributes.swift"
    )
    return try #require(file.classes.first)
  }
}
