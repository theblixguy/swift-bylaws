import Bylaws
import BylawsTestSupport
import Testing

@Suite("Matcher composition")
struct MatcherTests {
  @Test("Combinators skip an unused predicate", arguments: [true, false])
  func unusedPredicate(_ firstMatches: Bool) async {
    await confirmation(expectedCount: 0) { evaluated in
      let first = Matcher<Int>("match") { _ in firstMatches }
      let second = Matcher<Int>("match") { _ in
        evaluated()
        return true
      }
      let matcher = firstMatches ? first || second : first && second
      #expect(matcher(1) == firstMatches)
    }
  }

  @Test("Violation collection evaluates each predicate once")
  func singleEvaluation() async {
    await confirmation(expectedCount: 1) { evaluated in
      let matcher = Matcher<Int>("match") { _ in
        evaluated()
        return false
      }
      let violations = Selection(
        elements: [1],
        queryDescription: "numbers",
        rootPath: "/virtual"
      )
      .violations(of: matcher)
      #expect(violations.offenders == [1])
    }
  }

  @Test("Combinators evaluate and describe themselves")
  func combinatorsWork() async throws {
    let viewModels = try await SampleAppQueries.viewModels()
    let home = try #require(viewModels.named("HomeViewModel").first)

    let rule: Matcher<Class> = .inherits(from: "BaseViewModel") && .isFinal
    #expect(rule(home))
    #expect(rule
      .requirementDescription == "inherit from 'BaseViewModel' and be final")

    let negated = !rule
    #expect(!negated(home))
    #expect(negated
      .requirementDescription ==
      "not (inherit from 'BaseViewModel' and be final)")

    let either: Matcher<Class> = .named("Missing") || .suffixed("ViewModel")
    #expect(either(home))
    #expect(either
      .requirementDescription ==
      "(be named 'Missing' or have a name suffixed 'ViewModel')")

    let mixed: Matcher<Class> = .named("Missing") || (.isFinal && .isPublic)
    #expect(mixed
      .requirementDescription ==
      "(be named 'Missing' or (be final and be public))")
    #expect((!either).requirementDescription ==
      "not (be named 'Missing' or have a name suffixed 'ViewModel')")
  }

  @Test("A closure matcher uses its declared requirement phrase")
  func closureMatcher() async throws {
    let shortNames = Matcher<Class>("have a short name") { $0.name.count <= 12 }
    let classes = try await Codebase.sampleApp.classes

    #expect(classes.where(shortNames).map(\.name).contains("Helper"))
    #expect(shortNames.requirementDescription == "have a short name")
  }

  @Test("Conformance resolves through extensions in other files")
  func conformanceThroughExtension() async throws {
    let home = try #require(
      try await Codebase.sampleApp.classes.named("HomeViewModel").first
    )

    #expect(home.conforms(to: "Titled"))
    #expect(!home.directlyInherits(from: "Titled"))
    #expect(home.conforms(to: "BaseViewModel"))
  }

  @Test("Signature matchers narrow functions")
  func signatureMatchers() async throws {
    let stringReturners = try await Codebase.sampleApp.functions
      .where(.returns("String"))
    #expect(stringReturners.map(\.name).sorted() == ["format", "serialized"])

    let intTakers = try await Codebase.sampleApp.functions
      .where(.hasParameter(typed: "Int"))
    #expect(intTakers.map(\.name) == ["format"])

    let prettyTakers = try await Codebase.sampleApp.functions
      .where(.hasParameter(labelled: "pretty"))
    #expect(prettyTakers.map(\.name) == ["serialized"])
  }

  @Test("Attribute matchers accept the sigil form")
  func attributeMatchers() async throws {
    let tracked = try await Codebase.sampleApp.functions
      .where(.hasAttribute("@MainActor"))
    #expect(tracked.map(\.name) == ["track"])
  }
}
