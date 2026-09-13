import Bylaws
import Testing

@Suite("Name filters")
struct NameFilterTests {
  @Test("A filter accepts several values and matches any of them")
  func variadicFiltersMatchAny() async throws {
    let both = try await codebase.classes
      .suffixed("ViewModel", "ViewController")
    #expect(both.count == 2)

    let named = try await codebase.classes
      .named("HomeViewModel", "HomeViewController")
    #expect(named.count == 2)

    let underBoth = try await codebase.files
      .under("Sources/UI", "Sources/Domain")
    #expect(underBoth.count == 4)
  }

  @Test("A filter accepts a computed array of values")
  func arrayOverloadsMatch() async throws {
    let suffixes = ["ViewModel", "ViewController"]
    let both = try await codebase.classes.suffixed(suffixes)
    #expect(both.count == 2)
  }

  @Test("A matcher accepts several values and matches any of them")
  func variadicMatchersMatchAny() async throws {
    let violations = try await codebase.classes
      .violations(matching: .named("HomeViewModel", "HomeViewController"))
    #expect(violations.count == 2)
    #expect(violations
      .rule == "not be named 'HomeViewModel' or 'HomeViewController'")
  }

  @Test("A name filter matches a regular expression")
  func nameMatchingFilters() async throws {
    let flags = try await codebase.properties.nameMatching("ff_[a-z_]+")
    #expect(flags.map(\.name) == ["ff_new_checkout"])

    let matcher = try await codebase.properties
      .violations(of: try .nameMatching("ff_[a-z_]+"))
    #expect(matcher.isEmpty)
  }

  @Test("Invalid regular expression throws")
  func invalidPatternThrows() async {
    let expected = CodebaseError.invalidRegularExpression(pattern: "(")
    await #expect(throws: expected) {
      try await codebase.classes.nameMatching("(")
    }
    #expect(throws: expected) {
      try Matcher<Class>.nameMatching("(")
    }
  }

  @Test("Regular expression alternatives match the whole name")
  func alternationAnchorsTheWholeName() async throws {
    let matched = try await codebase.classes
      .nameMatching("HomeView|HomeViewModel")
    #expect(matched.map(\.name) == ["HomeViewModel"])
  }

  private let codebase = Codebase(root: .sources([
    "Sources/UI/HomeViewModel.swift": "final class HomeViewModel {}",
    "Sources/UI/HomeViewController.swift": "final class HomeViewController {}",
    "Sources/Domain/User.swift": "struct User {}",
    "Sources/Domain/FF.swift": "let ff_new_checkout = true",
  ]))
}
