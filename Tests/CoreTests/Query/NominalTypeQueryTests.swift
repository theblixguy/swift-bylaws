import Bylaws
import BylawsCore
import BylawsSemantics
import Testing

@Suite("Type queries")
struct NominalTypeQueryTests {
  @Test("Every type kind appears in one query in source order")
  func everyKindInSourceOrder() async throws {
    let types = try await Self.codebase.types.under("Sources/App")

    #expect(
      types.map(\.name) == [
        "HomeScreen", "HomeState", "HomeRoute", "HomeLoader", "Legacy",
        "Helper",
      ]
    )
    #expect(types.map(\.keyword) == [
      "class", "struct", "enum", "actor", "enum", "struct",
    ])
  }

  @Test("A protocol is not a type the query returns")
  func protocolIsNotIncluded() async throws {
    let names = try await Self.codebase.types.map(\.name)
    #expect(!names.contains("HomeRouting"))
  }

  @Test(
    "A kind matcher selects the types written with its keyword",
    arguments: [
      (Matcher<NominalType>.isClass, ["HomeScreen"]),
      (.isStruct, ["HomeState", "Helper"]),
      (.isEnum, ["HomeRoute", "Legacy"]),
      (.isActor, ["HomeLoader"]),
    ] as [(Matcher<NominalType>, [String])]
  )
  func kindMatcherSelects(
    _ matcher: Matcher<NominalType>,
    _ expected: [String]
  ) async throws {
    let selected = try await Self.codebase.types.where(matcher)
    #expect(selected.map(\.name).sorted() == expected.sorted())
  }

  @Test("A type reports its declaration's name, visibility and documentation")
  func typeForwardsItsDeclaration() async throws {
    let screen = try #require(
      await Self.codebase.types.named("HomeScreen").first
    )

    #expect(screen.isPublic)
    #expect(screen.isDocumented)
    #expect(screen.inherits(from: "Screen"))
    #expect(screen.enclosingTypeName == nil)
    #expect(screen.description.hasPrefix("class HomeScreen (Home.swift:"))
  }

  @Test("A nested type reports its qualified name")
  func nestedTypeKeepsItsQualifiedName() async throws {
    let helper = try #require(
      await Self.codebase.types.named("Helper").first
    )

    #expect(helper.qualifiedName == "Legacy.Helper")
  }

  @Test("A rule over every type checks each of them")
  func ruleChecksEveryType() async throws {
    let violations = try await Self.codebase.types
      .under("Sources/App")
      .violations(of: .hasDocumentation)

    #expect(violations.checkedCount == 6)
    #expect(violations.count == 5)
    #expect(!violations.offenders.map(\.name).contains("HomeScreen"))
  }

  private static let codebase = Codebase(root: .sources([
    "Sources/App/Home.swift": """
    /// The home screen.
    public final class HomeScreen: Screen {}
    struct HomeState {}
    enum HomeRoute { case list }
    actor HomeLoader {}
    protocol HomeRouting {}
    """,
    "Sources/App/Nested.swift": """
    enum Legacy {
      struct Helper {}
    }
    """,
  ]))
}
