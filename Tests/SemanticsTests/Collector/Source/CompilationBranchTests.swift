import BylawsSemantics
import Testing

@Suite("Written compilation branches")
struct CompilationBranchTests {
  @Test("Nested branches retain earlier conditions without evaluating them")
  func nestedConditions() throws {
    let file = try collect("""
    #if DEBUG
    #if os(iOS)
    flag = true
    #elseif os(macOS)
    flag = first && second
    #else
    flag = false
    #endif
    #elseif RELEASE
    flag = false
    #else
    flag = false
    #endif
    flag = false
    """)
    let assignments = file.assignments
    #expect(assignments.map { $0.compilationBranches.map(\.condition) } == [
      ["DEBUG", "os(iOS)"], ["DEBUG", "os(macOS)"], ["DEBUG", nil],
      ["RELEASE"], [nil], [],
    ])
    #expect(assignments[1].compilationBranches.last?
      .precedingConditions == ["os(iOS)"])
    #expect(assignments[2].compilationBranches.last?.precedingConditions == [
      "os(iOS)",
      "os(macOS)",
    ])
    #expect(assignments[4].compilationBranches.first?.precedingConditions == [
      "DEBUG",
      "RELEASE",
    ])
    #expect(assignments[1].value.compilationBranches == assignments[1]
      .compilationBranches)
    #expect(file.compilationBranches.map(\.name) == [
      "#if DEBUG", "#if os(iOS)", "#elseif os(macOS)", "#else",
      "#elseif RELEASE",
      "#else",
    ])
  }

  @Test("Branch bodies contain declaration locations but exclude directives")
  func declarationLocations() throws {
    let file = try collect("""
    #if DEBUG
    struct DebugStore {}
    #else
    struct Store {}
    #endif
    struct Other {}
    """)
    let branches = file.compilationBranches
    #expect(file.structs.map { declaration in
      branches.filter { $0.contains(declaration.location) }.map(\.name)
    } == [["#if DEBUG"], ["#else"], []])
    #expect(branches.allSatisfy { !$0.contains($0.location) })
    let location = try #require(file.structs.first?.location)
    #expect(!branches[0].contains(DeclarationLocation(
      filePath: "/virtual/Other.swift", line: location.line,
      column: location.column
    )))
  }

  @Test("Expressions and bindings retain branch context inside closures")
  func bodyContext() throws {
    let file = try collect("""
    #if DEBUG && !RELEASE
    let action = { let value = "é"; use(.public) }
    #endif
    """)
    let reference = try #require(file.expressions
      .first { $0.referenceName == "public" })
    #expect(reference.compilationBranches
      .map(\.condition) == ["DEBUG && !RELEASE"])
    #expect(file.variableBindings
      .map { $0.compilationBranches.map(\.condition) } == [
        ["DEBUG && !RELEASE"],
        ["DEBUG && !RELEASE"],
      ])
    let condition = try #require(file.expressions
      .first { $0.text == "DEBUG && !RELEASE" })
    #expect(condition.compilationBranches.isEmpty)
  }

  @Test("Empty branches contain no following declarations")
  func emptyBranches() throws {
    let file = try collect("""
    #if DEBUG
    #elseif RELEASE
    #else
    #endif
    struct Store {}
    """)
    let declaration = try #require(file.structs.first)
    #expect(file.compilationBranches.count == 3)
    #expect(file.compilationBranches
      .allSatisfy { !$0.contains(declaration.location) })
  }

  private func collect(_ source: String) throws -> SourceFile {
    try FileCollector.collect(
      source: source,
      path: "/virtual/Conditional.swift"
    )
  }
}
