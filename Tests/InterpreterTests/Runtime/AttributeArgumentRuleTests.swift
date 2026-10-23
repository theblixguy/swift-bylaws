import BylawsCore
import BylawsInterpreter
import Testing

@Suite("Portable attribute arguments")
struct AttributeArgumentRuleTests {
  @Test(
    "Source nodes retrieve attributes by name",
    arguments: ["Label", "@Label"]
  )
  func attributeLookup(name: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("attribute-lookup") {
        try await app.syntaxNodes(of: .classDeclaration)
          .violations(of: Matcher<SourceNode>("Read the first named attribute") { declaration in
            declaration.attribute(named: "\(name)")?.argument?.stringValue == "first"
              && declaration.attribute(named: "Missing") == nil
          })
      }
      """,
      sources: [
        "Sources/Store.swift": "@Label(\"first\") @Label(\"second\") class Store {}",
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.isEmpty)
  }

  @Test(
    "Unsupported inner arguments do not read enclosing attributes",
    arguments: [
      "@Inner",
      "@Inner(label: 1)",
      "@Inner(1, 2)",
    ]
  )
  func unsupportedInnerArguments(attribute: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("attribute-arguments") {
        try await app.syntaxNodes(of: .variableDeclaration)
          .violations(of: Matcher<SourceNode>("Keep arguments with their attribute") { declaration in
            declaration.attributes[0].argument == nil
          })
      }
      """,
      sources: [
        "Sources/Store.swift":
          "@Outer({ \(attribute) var value = 0; return value }) struct Store {}",
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.isEmpty)
  }
}
