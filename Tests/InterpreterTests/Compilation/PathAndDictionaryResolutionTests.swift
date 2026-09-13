import BylawsInterpreter
import Testing

@Suite("Portable path and dictionary diagnostics")
struct PathAndDictionaryResolutionTests {
  @Test("Unsupported calls rejected before execution", arguments: [
    ("let value = URL(fileURLWithPath: 42)", "the file path must be String"),
    (
      "let value = URL(string: \"https://example.com\")",
      "URL takes arguments (fileURLWithPath:)"
    ),
    (
      "let value = URL<Int>(fileURLWithPath: \"/Orders\")",
      "URL takes no generic arguments"
    ),
    (
      "let value = Dictionary(grouping: 42, by: \\.count)",
      "Dictionary grouping must be a sequence"
    ),
    (
      "let value = Dictionary(grouping: [\"x\"], by: \\.count)[\"x\"]",
      "the dictionary key must be Int"
    ),
    (
      "let value = Dictionary(grouping: [\"x\"]) { [$0] }",
      "Dictionary keys must be String, Int, Bool or URL"
    ),
    (
      "let value = Dictionary<String, [Int]>(grouping: [\"x\"], by: \\.count)",
      "the grouped dictionary must be"
    ),
    (
      "let value = Dictionary<Int>(grouping: [\"x\"], by: \\.count)",
      "Dictionary takes two generic arguments"
    ),
    (
      "let value = Dictionary(grouping: [1.5]) { $0 }",
      "Dictionary keys must be String, Int, Bool or URL"
    ),
    (
      "let value = Dictionary(grouping: [\"x\"], by: \\.count).mapValues { $0.isFinal }",
      "'isFinal' is not a supported member of Array"
    ),
  ])
  func rejectedCalls(_ binding: String, _ message: String) async throws {
    let (program, _) = try await diagnostics(forRules: """
    import Bylaws
    import Foundation
    let app = Codebase(including: ["Sources/**"])
    \(binding)
    let rules = [Rule("classes", "Classes final") {
      try await app.classes.violations(of: .isFinal)
    }]
    """)

    #expect(program.rules.isEmpty)
    #expect(
      program.errors.contains { $0.message.contains(message) },
      "\(program.errors)"
    )
  }

  @Test("Grouping rejects incompatible helper signatures", arguments: [
    (
      "func group(_ value: Int) -> Int { value }",
      "the collection element must be Int"
    ),
    (
      "func group(_ first: String, _ second: String) -> String { first }",
      "the collection helper takes one parameter"
    ),
    (
      "func group(_ value: String) async -> String { value }",
      "the collection helper must be synchronous and nonthrowing"
    ),
    (
      "func group(_ value: String) throws -> String { value }",
      "the collection helper must be synchronous and nonthrowing"
    ),
  ])
  func helperSignatures(_ helper: String, _ message: String) async throws {
    let (program, _) = try await diagnostics(forRules: """
    import Bylaws
    \(helper)
    let app = Codebase(including: ["Sources/**"])
    let rules = [Rule("groups", "Names grouped") {
      let groups = Dictionary(grouping: ["one"], by: group)
      return try await app.classes.violations(of: .isFinal)
    }]
    """)

    #expect(program.rules.isEmpty)
    #expect(
      program.errors.contains { $0.message.contains(message) },
      "\(program.errors)"
    )
  }
}
