import BylawsCore
import BylawsSemantics
import BylawsTestSupport
import Testing
@testable import BylawsInterpreter

@Suite("Compiled inheritance requirements")
struct InheritanceRequirementTests {
  @Test("Naming and path checks use written declarations", arguments: [
    "named", "suffixed", "prefixed", "nameMatching", "isFinal",
    "isPublic", "hasVisibility", "hasAttribute", "hasDocumentation",
    "isClass", "isStruct", "isEnum", "isActor",
  ])
  func writtenDeclarations(_ name: String) {
    let query = Self.query(check: .of(.leaf(Self.call(name))))
    #expect(query.canUseDeclarationsAsWritten)
  }

  @Test(
    "Inherited and unknown checks request resolved declarations",
    arguments: [
      "inherits", "directlyInherits", "conforms", "directlyConforms",
      "declaresInheritance", "customMatcher",
    ]
  )
  func resolvedDeclarations(_ name: String) {
    let query = Self.query(check: .of(.leaf(Self.call(name))))
    #expect(!query.canUseDeclarationsAsWritten)
  }

  @Test("Boolean composition keeps inherited requirements")
  func combinedRequirements() {
    let name = MatcherExpression.leaf(Self.call("named"))
    let inherits = MatcherExpression.leaf(Self.call("inherits"))
    #expect(Self.query(check: .matching(.not(name)))
      .canUseDeclarationsAsWritten)
    #expect(!Self.query(check: .of(.and(name, inherits)))
      .canUseDeclarationsAsWritten)
    #expect(!Self.query(check: .of(.or(inherits, name)))
      .canUseDeclarationsAsWritten)
    #expect(!Self.query(check: .matching(.not(inherits)))
      .canUseDeclarationsAsWritten)
  }

  @Test("Unknown filters keep resolved declarations")
  func unknownFilter() {
    var query = Self.query(check: .outsidePaths(["Sources"]))
    #expect(query.canUseDeclarationsAsWritten)
    query.filters = [Self.call("customFilter")]
    #expect(!query.canUseDeclarationsAsWritten)
  }

  @Test("Mixed compiled rules retain aliases and extension conformances")
  func mixedRules() async throws {
    let project = try rulesProject(
      rules: """
      Rule("names", "Child name retained") {
        app.classes.named("Child").violations(of: .named("Child"))
      },
      Rule("alias", "Alias resolves to base") {
        app.classes.named("Parent").violations(of: .inherits(from: "Base"))
      },
      Rule("direct", "Extension conformance retained") {
        app.classes.named("Parent").violations(of: .directlyConforms(to: "Named"))
      },
      Rule("transitive", "Child inherits extension conformance") {
        app.classes.named("Child").violations(of: .conforms(to: "Named"))
      },
      Rule("custom", "Custom matcher sees inherited conformance") {
        let matcher = Matcher<Class>("conform to Named") { $0.conforms(to: "Named") }
        return try await app.classes.named("Child").violations(of: matcher)
      }
      """,
      sources: ["Sources/Models.swift": """
      protocol Named {}
      class Base {}
      typealias Alias = Base
      class Parent: Alias {}
      class Child: Parent {}
      extension Parent: Named {}
      """]
    )
    let program = try await loadedProgram(in: project)
    try #require(program.rules.count == 5)
    for rule in program.rules {
      let violations = try await rule.violations()
      #expect(violations.checkedCount == 1)
      #expect(violations.isEmpty)
    }
  }

  private static func query(check: Check) -> QueryExpression {
    QueryExpression(
      codebase: "app",
      accessor: call("classes"),
      check: check
    )
  }

  private static func call(_ name: String) -> ParsedCall {
    ParsedCall(
      name: name,
      arguments: [],
      location: .start(of: "Bylaws.swift")
    )
  }
}
