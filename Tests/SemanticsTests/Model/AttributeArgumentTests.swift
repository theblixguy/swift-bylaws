import BylawsSemantics
import Testing

@Suite("Attribute arguments")
struct AttributeArgumentTests {
  @Test(
    "Unsupported inner arguments do not read enclosing attributes",
    arguments: [
      "@Inner",
      "@Inner(label: 1)",
      "@Inner(1, 2)",
    ]
  )
  func unsupportedInnerArguments(attribute: String) throws {
    let file = try FileCollector.collect(
      source: "@Outer({ \(attribute) var value = 0; return value }) struct Store {}",
      path: "/virtual/Attributes.swift"
    )
    let declaration = try #require(file.syntaxNodes(of: .variableDeclaration)
      .first)
    let inner = try #require(declaration.attributes.first)

    #expect(inner.name == "Inner")
    #expect(inner.argument == nil)
    #expect(file.structs.first?.attributes.first?.argument != nil)
  }

  @Test("Single inner argument retains its own expression")
  func singleInnerArgument() throws {
    let file = try FileCollector.collect(
      source: "@Outer({ @Inner(1) var value = 0; return value }) struct Store {}",
      path: "/virtual/Attributes.swift"
    )
    let declaration = try #require(file.syntaxNodes(of: .variableDeclaration)
      .first)
    let inner = try #require(declaration.attributes.first)

    #expect(try inner.argument?.source.text == "1")
  }
}
