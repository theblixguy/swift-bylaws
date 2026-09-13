import Bylaws
import BylawsCore
import BylawsSemantics
import Testing

@Suite("Matchers over declaration members")
struct MemberMatcherTests {
  @Test("Nested matchers retain the innermost failed declaration")
  func nestedLocation() async throws {
    let app = Codebase(root: .sources(["Model.swift": """
    class Model {
      func load() {}
    }
    """]))
    let files = try await app.files
    let matcher = Matcher<SourceFile>.all(
      \.classes,
      matching: .all(\.functions, matching: .isAsync)
    )

    let violations = files.violations(of: matcher).erased()

    #expect(violations.offenders.first?.location.line == 2)
    #expect(violations
      .rule == "have all selected members have all selected members be async")
  }

  @Test("Member quantifiers handle empty and mixed collections", arguments: [
    ("", true, false, true),
    ("func load() async {}", true, true, false),
    ("func load() {}", false, false, true),
    ("func load() async {}\nfunc save() {}", false, true, false),
  ])
  func quantifiers(
    source: String,
    all: Bool,
    any: Bool,
    none: Bool
  ) async throws {
    let app =
      Codebase(root: .sources(["Model.swift": "class Model { \(source) }"]))
    let model = try #require(await app.classes.first)

    #expect(Matcher<Class>.all(\.functions, matching: .isAsync)(model) == all)
    #expect(Matcher<Class>.any(\.functions, matching: .isAsync)(model) == any)
    #expect(Matcher<Class>.none(\.functions, matching: .isAsync)(model) == none)
  }

  @Test("Failed member retains its source location")
  func memberLocation() async throws {
    let app = Codebase(root: .sources(["Model.swift": """
    class Model {
      func load() async {}
      func save() {}
    }
    """]))
    let classes = try await app.classes
    let matcher = Matcher<Class>.all(\.functions, matching: .isAsync)
    let violations = classes.violations(of: matcher).erased()

    #expect(violations.offenders.count == 1)
    #expect(violations.offenders.first?.location.line == 3)
    #expect(violations.offenders.first?.name == "Model")
  }

  @Test("Negated member match reports the matching member")
  func forbiddenMember() async throws {
    let app = Codebase(root: .sources(["Model.swift": """
    class Model {
      func load() async {}
    }
    """]))
    let classes = try await app.classes
    let matcher = Matcher<Class>.none(\.functions, matching: .isAsync)

    #expect(classes.violations(of: matcher).erased().offenders.first?.location
      .line == 2)
  }

  @Test("Boolean key paths support requirements and bans")
  func booleanChecks() async throws {
    let app =
      Codebase(
        root: .sources(["Model.swift": "class Open {}\nfinal class Closed {}"])
      )
    let classes = try await app.classes

    #expect(classes.violations(of: \.isFinal).offenders.map(\.name) == ["Open"])
    #expect(classes.violations(matching: \.isFinal).offenders
      .map(\.name) == ["Closed"])
  }
}
