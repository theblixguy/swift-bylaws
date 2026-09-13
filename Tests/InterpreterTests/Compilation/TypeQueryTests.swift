import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Interpreted type queries")
struct TypeQueryTests {
  @Test("A rule over every type checks the four kinds")
  func ruleChecksEveryKind() async throws {
    let project = try Self.project(rules: """
    Rule("documented-types", "Types carry documentation") {
      app.types.violations(of: .hasDocumentation)
    }
    """)

    let program = try await discoveredProgram(in: project)

    let violations = try await #require(program.rules.first).violations()
    #expect(violations.checkedCount == 4)
    #expect(violations.offenders.compactMap(\.name) == [
      "HomeState", "HomeRoute", "HomeLoader",
    ])
  }

  @Test(
    "A kind matcher matches types written with its keyword",
    arguments: [
      (".isClass", ["HomeState", "HomeRoute", "HomeLoader"]),
      (".isStruct", ["HomeScreen", "HomeRoute", "HomeLoader"]),
      (".isEnum", ["HomeScreen", "HomeState", "HomeLoader"]),
      (".isActor", ["HomeScreen", "HomeState", "HomeRoute"]),
    ] as [(String, [String])]
  )
  func kindMatcherHolds(
    _ matcher: String,
    _ offenders: [String]
  ) async throws {
    let project = try Self.project(rules: """
    Rule("kinds", "Every type is written with the one keyword") {
      app.types.violations(of: \(matcher))
    }
    """)

    let program = try await discoveredProgram(in: project)

    let violations = try await #require(program.rules.first).violations()
    #expect(violations.checkedCount == 4)
    #expect(violations.offenders.compactMap(\.name).sorted() == offenders
      .sorted())
  }

  @Test("A matcher for one kind alone does not apply to the query")
  func kindOnlyMatcherDiagnoses() async throws {
    let project = try Self.project(rules: """
    Rule("final-types", "Types say final") {
      app.types.violations(of: .isFinal)
    }
    """)

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)
    let diagnostic = try #require(program.errors.first)
    #expect(diagnostic.message.contains("'isFinal' does not apply"))
  }

  private static let sources: [String: String] = [
    "Sources/App/Home.swift": """
    /// The home screen.
    public final class HomeScreen {}
    struct HomeState {}
    enum HomeRoute { case list }
    actor HomeLoader {}
    """,
  ]

  private static func project(rules: String) throws -> TemporaryProject {
    try TemporaryProject(files: sources.merging(
      ["Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      \(rules)
      """],
      uniquingKeysWith: { first, _ in first }
    ))
  }
}
