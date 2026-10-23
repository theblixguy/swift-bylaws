import BylawsSemantics
import Testing

@Suite("Source node property projections")
struct SourceNodePropertyProjectionTests {
  @Test("Global and nested properties retain declaration context")
  func enclosingTypes() throws {
    let file = try collect("""
    let global = 0
    struct Outer {
      let member: Int
      struct Inner {
        let nested: Int
      }
    }
    """)
    let properties = file.syntaxNodes(of: .variableDeclaration)
      .compactMap(\.property)
    #expect(properties.map(\.name) == ["global", "member", "nested"])
    #expect(properties.map(\.enclosingTypeName) == [
      nil,
      "Outer",
      "Outer.Inner",
    ])
    #expect(properties.map(\.visibility) == [.internal, .internal, .internal])
    #expect(properties == file.properties)
    for (property, collected) in zip(properties, file.properties) {
      #expect(try property.source == collected.source)
      #expect(try property.source
        .filePath == "/virtual/Current/Properties.swift")
    }
  }

  @Test("Extension and protocol members retain inherited visibility")
  func inheritedVisibility() throws {
    let file = try collect("""
    public struct Store {}
    public extension Store {
      var exposed: Int { 1 }
    }
    private extension Store {
      var hidden: Int { 2 }
    }
    public protocol Requirement {
      var required: Int { get }
    }
    """)
    let properties = file.syntaxNodes(of: .variableDeclaration)
      .compactMap(\.property)
    #expect(properties.map(\.name) == ["exposed", "hidden", "required"])
    #expect(properties.map(\.enclosingTypeName) == [
      "Store",
      "Store",
      "Requirement",
    ])
    #expect(properties.map(\.visibility) == [.public, .private, .public])
    let requirement = try #require(properties.last)
    let collected = try #require(file.protocols.first?.requiredProperties.first)
    #expect(requirement == collected)
    #expect(try requirement.source == collected.source)
  }

  @Test("Local and multiple bindings have no property projection")
  func unsupportedBindings() throws {
    let file = try collect("""
    let value = 0
    func work() {
      let value = 1
    }
    struct Store {
      let first, second: Int
    }
    """)
    let nodes = file.syntaxNodes(of: .variableDeclaration)
    let global = try #require(nodes.first { $0.text == "let value = 0" })
    let local = try #require(nodes.first { $0.text == "let value = 1" })
    let multiple = try #require(nodes
      .first { $0.text == "let first, second: Int" })
    #expect(global.property?.name == "value")
    #expect(local.property == nil)
    #expect(multiple.property == nil)
  }

  @Test("Child and parent views retain collected property lookup")
  func relatedNodes() throws {
    let file = try collect("struct Outer { let value: Int }")
    let root = try #require(file.syntaxNodes(of: .sourceFile).first)
    let declaration = try #require(root.descendants
      .first { $0.kind == .structDeclaration })
    let member = try #require(declaration.members.first)
    let child = try #require(declaration.children
      .first { $0.kind == .variableDeclaration })
    let parent = try #require(child.parent)
    let collected = try #require(file.properties.first)
    #expect(member.property == collected)
    #expect(child.property == collected)
    #expect(parent.members.first?.property == collected)
    #expect(member.property?.enclosingTypeName == "Outer")
  }

  private func collect(_ source: String) throws -> SourceFile {
    try FileCollector.collect(
      source: source,
      path: "/virtual/Current/Properties.swift"
    )
  }
}
