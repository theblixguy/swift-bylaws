import BylawsCore
import BylawsSemantics
import Testing

@Suite("Deferred inheritance")
struct DeferredInheritanceTests {
  @Test("Raw and resolved projections keep separate storage")
  func separateProjections() async throws {
    let codebase = Self.codebase()
    let raw = try await codebase.usingDeclarations(.asWritten).classes
    let resolved = try await codebase.classes
    let rawAgain = try await codebase.usingDeclarations(.asWritten).classes
    let resolvedAgain = try await codebase.classes

    #expect(raw.storage !== resolved.storage)
    #expect(raw.storage === rawAgain.storage)
    #expect(resolved.storage === resolvedAgain.storage)
    #expect(raw.map(\.name) == resolved.map(\.name))
    let rawChild = try #require(raw.named("Child").first)
    let resolvedChild = try #require(resolved.named("Child").first)
    #expect(!rawChild.inherits(from: "Base"))
    #expect(resolvedChild.inherits(from: "Base"))
    #expect(resolvedChild.conforms(to: "Named"))
    #expect(!rawChild.conforms(to: "Named"))
  }

  @Test("Concurrent mixed queries preserve inherited information")
  func concurrentQueries() async throws {
    let codebase = Self.codebase()
    let selections = try await withThrowingTaskGroup(
      of: Selection<Class>.self
    ) { group in
      for index in 0..<40 {
        group.addTask {
          let declarations: ParsedCodebase.Declarations = index
            .isMultiple(of: 2)
            ? .asWritten : .resolved
          return try await codebase.usingDeclarations(declarations).classes
        }
      }
      var selections: [Selection<Class>] = []
      for try await selection in group { selections.append(selection) }
      return selections
    }

    let resolved = try await codebase.classes
    let raw = try await codebase.usingDeclarations(.asWritten).classes
    #expect(selections.count(where: { $0.storage === resolved.storage }) == 20)
    #expect(selections.count(where: { $0.storage === raw.storage }) == 20)
    #expect(resolved.named("Parent").first?
      .directlyConforms(to: "Named") == true)
    #expect(resolved.named("Child").first?.conforms(to: "Named") == true)
  }

  @Test("Public custom matchers receive resolved declarations")
  func customMatcher() async throws {
    let codebase = Self.codebase()
    _ = try await codebase.usingDeclarations(.asWritten).classes
    let matcher = Matcher<Class>("inherit from Base") {
      $0.inherits(from: "Base")
    }
    let inherited = try await codebase.classes.where(matcher)
    #expect(inherited.map(\.name) == ["Parent", "Child"])
  }

  private static func codebase() -> Codebase {
    Codebase(root: .sources([
      "Models.swift": """
      protocol Named {}
      class Base {}
      typealias Alias = Base
      class Parent: Alias {}
      class Child: Parent {}
      extension Parent: Named {}
      """,
    ]))
  }
}
