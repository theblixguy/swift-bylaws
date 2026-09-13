import Bylaws
import BylawsTestSupport
import Foundation
import Testing

@Suite("Transitive inheritance", .tags(.architecture))
struct TransitiveInheritanceTests {
  init() throws {
    project = try TemporaryProject(
      files: [
        "Sources/Chain.swift": """
        class Grandparent {}
        class Parent: Grandparent {}
        class Child: Parent {}
        """,
        "Sources/Protocols.swift": """
        protocol Persistable {}
        protocol Cacheable: Persistable {}
        struct Record: Cacheable {}
        """,
        "Sources/Extended.swift": """
        protocol Titled {}
        extension Parent: Titled {}
        """,
        "Sources/Aliased.swift": """
        typealias ViewModelBase = Grandparent
        class HomeViewModel: ViewModelBase {}
        """,
        "Sources/External.swift": """
        class Screen: UIViewController {}
        """,
        "Sources/Cycle.swift": """
        class Ouroboros: Serpent {}
        class Serpent: Ouroboros {}
        """,
        "Sources/Generic.swift": """
        class Container<Value>: Grandparent {}
        class IntContainer: Container<Int> {}
        """,
      ]
    )
  }

  @Test("Class inherits through intermediate class")
  func inheritsThroughIntermediate() async throws {
    let child = try #require(await codebase.classes.named("Child").first)
    #expect(child.inherits(from: "Parent"))
    #expect(child.inherits(from: "Grandparent"))
    #expect(child.directlyInherits(from: "Parent"))
    #expect(!child.directlyInherits(from: "Grandparent"))
  }

  @Test("Type conforms through protocol inheritance")
  func conformsThroughProtocolChain() async throws {
    let record = try #require(await codebase.structs.named("Record").first)
    #expect(record.conforms(to: "Cacheable"))
    #expect(record.conforms(to: "Persistable"))
    #expect(record.directlyConforms(to: "Cacheable"))
    #expect(!record.directlyConforms(to: "Persistable"))
  }

  @Test("Extension conformance applies to subclasses")
  func extensionConformanceCarriesDown() async throws {
    let child = try #require(await codebase.classes.named("Child").first)
    #expect(child.conforms(to: "Titled"))
    #expect(!child.directlyConforms(to: "Titled"))
  }

  @Test("Inheritance resolution follows a typealias to its target")
  func typealiasResolves() async throws {
    let viewModel = try #require(
      await codebase.classes.named("HomeViewModel").first
    )
    #expect(viewModel.inherits(from: "ViewModelBase"))
    #expect(viewModel.inherits(from: "Grandparent"))
  }

  @Test("Inheritance stops at external types")
  func externalChainIsInvisible() async throws {
    let screen = try #require(await codebase.classes.named("Screen").first)
    #expect(screen.inherits(from: "UIViewController"))
    #expect(!screen.inherits(from: "UIResponder"))
  }

  @Test("A generic parent matches its simple name and inheritance chain")
  func genericParentResolves() async throws {
    let container = try #require(
      await codebase.classes.named("IntContainer").first
    )
    #expect(container.inherits(from: "Container<Int>"))
    #expect(container.inherits(from: "Container"))
    #expect(container.inherits(from: "Grandparent"))
  }

  @Test("An inheritance cycle in invalid source does not prevent completion")
  func cycleDoesNotHang() async throws {
    let ouroboros = try #require(
      await codebase.classes.named("Ouroboros").first
    )
    #expect(ouroboros.inherits(from: "Serpent"))
  }

  @Test("The transitive matchers narrow selections")
  func matchersUseTheWalk() async throws {
    let titled = try await codebase.classes.where(.conforms(to: "Titled"))
    #expect(titled.map(\.name).sorted() == ["Child", "Parent"])

    let directlyTitled = try await codebase.classes
      .where(.directlyConforms(to: "Titled"))
    #expect(directlyTitled.map(\.name) == ["Parent"])
  }

  private let project: TemporaryProject

  private var codebase: Codebase {
    Codebase(root: .directory(project.rootURL.path))
  }
}
