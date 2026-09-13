import BylawsInterpreter
import Testing

@Suite("Rules-file vocabulary diagnostics")
struct RulesFileVocabularyDiagnosticTests {
  @Test("A diagnostic names an unknown query and lists available queries")
  func unknownQuery() async throws {
    let (program, _) = try await diagnostics(forRules: """
    let app = Codebase(including: ["Sources/**"])
    Rule("r", "Rule") { app.widgets.violations(of: .isFinal) }
    """)

    let diagnostic = try #require(program.errors.first)
    #expect(diagnostic.message.contains("'widgets' is not a query"))
    #expect(diagnostic.hint?.contains("classes") == true)
    #expect(program.rules.isEmpty)
  }

  @Test("A query rejects arguments that its registered contract does not allow")
  func queryArgumentDiagnoses() async throws {
    let (program, _) = try await diagnostics(forRules: """
    let app = Codebase(including: ["Sources/**"])
    Rule("r", "Rule") { app.classes("Value").violations(of: .isFinal) }
    """)

    let diagnostic = try #require(program.errors.first)
    #expect(diagnostic.message == "'classes' takes no arguments")
    #expect(program.rules.isEmpty)
  }

  @Test(
    "An invalid rule body produces a diagnostic with its location",
    arguments: WrongRuleBodyCase.cases
  )
  func wrongBodyDiagnoses(_ testCase: WrongRuleBodyCase) async throws {
    let (program, _) = try await diagnostics(forRules: """
    let app = Codebase(including: ["Sources/**"])
    Rule("r", "Rule") {
      \(testCase.body)
    }
    """)

    let diagnostic = try #require(program.errors.first)
    try expectDiagnostic(
      diagnostic,
      messageContaining: testCase.message,
      hintContaining: testCase.hint
    )
  }

  @Test("A diagnostic for an unknown codebase includes a declaration example")
  func unknownBinding() async throws {
    let (program, _) = try await diagnostics(forRules: """
    Rule("r", "Rule") { app.classes.violations(of: .isFinal) }
    """)

    let diagnostic = try #require(program.errors.first)
    #expect(diagnostic.message.contains("'app' is not a codebase"))
    #expect(diagnostic.hint?.contains("let app = Codebase") == true)
  }

  @Test("One parse reports every vocabulary error")
  func accumulatesDiagnostics() async throws {
    let (program, _) = try await diagnostics(forRules: """
    let app = Codebase(including: ["Sources/**"])
    Rule("one", "First") { app.widgets.violations(of: .isFinal) }
    Rule("two", "Second") { app.files.violations(of: .isFinal) }
    Rule("three", "Third") { app.classes.violations(of: .isFinal) }
    """)

    #expect(program.errors.count == 2)
    #expect(program.rules.count == 1)
  }

  @Test("A computed Codebase array produces a diagnostic")
  func computedCodebaseArrayDiagnoses() async throws {
    let (program, _) = try await diagnostics(forRules: """
    let app = Codebase(including: ["Sources/**"] + [])
    Rule("r", "Rule") { app.classes.violations(of: .isFinal) }
    """)

    let diagnostic = try #require(program.errors.first)
    #expect(
      diagnostic.message
        == "'including' takes an array of glob pattern literals"
    )
  }

  @Test("An unknown matcher argument label produces a diagnostic")
  func matcherArgumentLabelDiagnoses() async throws {
    let (program, _) = try await diagnostics(forRules: """
    let app = Codebase(including: ["Sources/**"])
    Rule("r", "Rule") {
      app.files.violations(matching: .calls(named: "print"))
    }
    """)

    let diagnostic = try #require(program.errors.first)
    #expect(
      diagnostic.message
        == "'calls' takes string literals or one string array"
    )
  }

  @Test("An unknown filter argument label produces a diagnostic")
  func filterArgumentLabelDiagnoses() async throws {
    let (program, _) = try await diagnostics(forRules: """
    let app = Codebase(including: ["Sources/**"])
    Rule("r", "Rule") {
      app.classes.suffixed(names: "ViewModel").violations(of: .isFinal)
    }
    """)

    let diagnostic = try #require(program.errors.first)
    #expect(
      diagnostic.message
        == "'suffixed' takes string literals or one string array"
    )
  }

  @Test(
    "An invalid name pattern reports a diagnostic",
    arguments: invalidNamePatternBodies
  )
  func invalidNamePatternDiagnoses(_ body: String) async throws {
    let (program, _) = try await diagnostics(forRules: """
    let app = Codebase(including: ["Sources/**"])
    Rule("r", "Rule") { \(body) }
    """)

    let diagnostic = try #require(program.errors.first)
    #expect(
      diagnostic.message
        == "Bylaws cannot compile '(' as a regular expression. Fix the pattern."
    )
    #expect(program.rules.isEmpty)
  }

  @Test(
    "The interpreter accepts every added prebuilt matcher",
    arguments: addedMatcherCases
  )
  func addedMatcherParses(_ query: String, _ matcher: String) async throws {
    let (program, _) = try await diagnostics(forRules: """
    let app = Codebase(including: ["Sources/**"])
    Rule("r", "Rule") {
      app.\(query).violations(of: \(matcher))
    }
    """)

    #expect(program.errors.isEmpty)
    #expect(program.rules.count == 1)
  }

  @Test("An import graph rule recommends the compiled-rule API")
  func importGraphDiagnoses() async throws {
    let (program, _) = try await diagnostics(forRules: """
    let app = Codebase(including: ["Sources/**"])
    Rule("r", "Rule") { app.importGraph() }
    """)

    let diagnostic = try #require(program.errors.first)
    #expect(
      diagnostic.message
        == "'importGraph' returns an import graph, not violations"
    )
    #expect(diagnostic.hint == "read the import graph in a test target")
  }

  private static let addedMatcherCases: [(String, String)] = [
    ("functions", ".hasVisibility(atLeast: .public)"),
    ("functions", ".isMutating"),
    ("functions", ".isDynamic"),
    ("functions", ".isAsync"),
    ("functions", ".isThrowing"),
    ("functions", ".isNonisolated"),
    ("functions", ".returnsOptional"),
    ("functions", ".hasParameter(referencing: [\"Order\"])"),
    ("functions", ".hasParameter(referencing: [])"),
    ("properties", ".isNonisolatedUnsafe"),
    ("calls", ".hasArgumentLabel(\"named\")"),
  ]

  private static let invalidNamePatternBodies = [
    "app.classes.nameMatching(\"(\").violations(of: .isFinal)",
    "app.classes.violations(of: .nameMatching(\"(\"))",
  ]
}

struct WrongRuleBodyCase: Sendable, CustomTestStringConvertible {
  let body: String
  let message: String
  let hint: String?

  var testDescription: String { message }

  static let cases = [
    WrongRuleBodyCase(
      body: "app.files.violations(of: .isFinal)",
      message: "'isFinal' does not apply",
      hint: nil
    ),
    WrongRuleBodyCase(
      body: """
      let selection = app.classes
          return selection.violations(of: .isFinal)
      """,
      message: "one query expression",
      hint: "test target"
    ),
  ]
}
