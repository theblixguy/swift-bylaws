import Bylaws
import Testing

@Suite("Key-path matchers")
struct KeyPathMatcherTests {
  @Test("Comparison operators create matchers from key paths and values")
  func comparisonsBuildMatchers() async throws {
    let short = try await codebase.functions
      .where(\.bodyLineCount <= 3)
    #expect(short.map(\.name) == ["save"])

    let long = try await codebase.functions
      .violations(of: \.bodyLineCount <= 3)
    #expect(long.count == 1)
    #expect(long.offenders.first?.name == "render")
  }

  @Test("An equality matcher compares through an optional key path")
  func equalityComparesOptionals() async throws {
    let contained = try await codebase.functions
      .where(.calls("UserDefaults"))
      .where(\.enclosingTypeName == "PreferencesStore")
    #expect(contained.count == 1)

    let elsewhere = try await codebase.functions
      .where(\.enclosingTypeName != "Report")
    #expect(elsewhere.map(\.name) == ["save"])
  }

  @Test("A key-path matcher composes with the matcher operators")
  func composesWithOperators() async throws {
    let violations = try await codebase.functions
      .violations(of: !(\.bodyLineCount > 3) || \.enclosingTypeName == "Report")
    #expect(violations.isEmpty)
  }

  @Test("A key-path matcher compares cyclomatic complexity")
  func complexityBuildsMatchers() async throws {
    let violations = try await codebase.functions
      .violations(of: \.cyclomaticComplexity <= 1)

    #expect(violations.offenders.map(\.name) == ["render"])
  }

  @Test("The requirement phrase names the property and the bound")
  func phrasesNameThePropertyAndBound() {
    let atMost: Matcher<Function> = \.bodyLineCount <= 300
    #expect(atMost.requirementDescription.hasSuffix("of at most 300"))

    let named: Matcher<Function> = \.enclosingTypeName == "PreferencesStore"
    #expect(
      named.requirementDescription.hasSuffix("of 'PreferencesStore'")
    )
  }

  private let codebase = Codebase(root: .sources([
    "Sources/App/Store.swift": """
    struct PreferencesStore {
      func save() {
        UserDefaults.standard.set(true, forKey: "seen")
      }
    }
    """,
    "Sources/App/Long.swift": """
    struct Report {
      func render() {
        let a = 1
        let b = 2
        let c = a + b
        if c > 0 { print(c) }
        guard c < 10 else { return }
      }
    }
    """,
  ]))
}
