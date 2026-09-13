import BylawsCore
import BylawsInterpreter
import BylawsTestSupport
import Testing

@Suite("Portable dictionaries")
struct DictionaryEvaluationTests {
  @Test("Dictionary groups values and maps each group")
  func groups() async throws {
    let project = try rulesProject(
      rules: """
      Rule("groups", "Names grouped by length") {
        let groups = Dictionary(grouping: ["one", "two", "four"], by: \\.count)
          .mapValues { Set($0) }
        let matches = Matcher<Class>("have the expected groups") { _ in
          groups[3] == Set(["one", "two"])
            && groups[4]?.contains("four") == true
            && groups[5] == nil
        }
        return try await app.classes.violations(of: matches)
      },
      """,
      sources: ["Sources/App.swift": "class Example {}"]
    )

    let program = try await loadedProgram(in: project)
    let violations = try await #require(program.rules.first).violations()

    #expect(violations.isEmpty)
    #expect(violations.checkedCount == 1)
  }

  @Test("Dictionary preserves group order and optional values")
  func dictionaryValues() async throws {
    let project = try rulesProject(
      rules: """
      Rule("groups", "Group contents preserved") {
        let groups: [Int: [String]] = Dictionary(grouping: ["one", "two", "one"], by: \\.count)
        let empty = Dictionary<Int, [String]>(grouping: [], by: \\.count)
        let optionalValues = groups.mapValues { $0.first }
        let optionalGroups: [Int: [String]]? = groups
        let matches = Matcher<Class>("preserve group contents") { _ in
          groups[3] == ["one", "two", "one"]
            && groups.count == 1 && !groups.isEmpty
            && empty.count == 0 && empty.isEmpty
            && empty[3] == nil
            && optionalValues[3] == "one"
            && optionalValues[4] == nil
            && optionalGroups?[3]?.count == 3
        }
        return try await app.classes.violations(of: matches)
      },
      """,
      sources: ["Sources/App.swift": "class Example {}"]
    )

    let program = try await loadedProgram(in: project)
    let violations = try await #require(program.rules.first).violations()

    #expect(violations.isEmpty)
    #expect(violations.checkedCount == 1)
  }

  @Test("Dictionary groups by supported key types", arguments: [
    "Dictionary(grouping: [1, 2, 1]) { $0 }[1] == [1, 1]",
    "Dictionary(grouping: [9223372036854775807, 9223372036854775806]) { $0 }[9223372036854775807] == [9223372036854775807]",
    "Dictionary(grouping: Set([\"one\", \"two\"]), by: \\.count)[3]?.count == 2",
    "Dictionary(grouping: [true, false, true]) { $0 }[true] == [true, true]",
    "Dictionary(grouping: [1, 2]) { URL(fileURLWithPath: \"/Orders\") }[URL(fileURLWithPath: \"/Orders\")] == [1, 2]",
  ])
  func keyTypes(_ expression: String) async throws {
    let project = try TemporaryProject(files: [
      "ProjectRules.swift": """
      import Bylaws
      import Foundation
      let app = Codebase(including: ["Sources/**"])
      let rules = [Rule("keys", "Dictionary keys preserve their types") {
        let matches = Matcher<Class>("match the group") { _ in \(expression) }
        return try await app.classes.violations(of: matches)
      }]
      """,
      "Sources/App.swift": "class Example {}",
    ])

    let program = try await loadedProgram(in: project)
    let violations = try await #require(program.rules.first).violations()

    #expect(violations.isEmpty)
    #expect(violations.checkedCount == 1)
  }

  @Test("Named helper maps dictionary values with its argument label")
  func labelledHelper() async throws {
    let project = try TemporaryProject(files: [
      "ProjectRules.swift": """
      import Bylaws
      func countNames(in names: [String]) -> Int { names.count }
      let app = Codebase(including: ["Sources/**"])
      let rules = [Rule("counts", "Names counted by length") {
        let counts = Dictionary(grouping: ["one", "two", "four"], by: \\.count)
          .mapValues(countNames)
        let matches = Matcher<Class>("count grouped names") { _ in
          counts[3] == 2 && counts[4] == 1
        }
        return try await app.classes.violations(of: matches)
      }]
      """,
      "Sources/App.swift": "class Example {}",
    ])
    let program = try await loadedProgram(in: project)

    let violations = try await #require(program.rules.first).violations()

    #expect(violations.isEmpty)
    #expect(violations.checkedCount == 1)
  }

  @Test("Present nil value differs from missing dictionary key")
  func nilValues() async throws {
    let project = try rulesProject(
      rules: """
      Rule("optional-values", "Missing keys differ from nil values") {
        let groups = Dictionary(grouping: ["one"], by: \\.count)
        let nilValues = groups.mapValues { _ in
          let value: String? = nil
          return value
        }
        let matches = Matcher<Class>("keep nil values") { _ in
          nilValues.count == 1 && nilValues[3] != nil && nilValues[4] == nil
        }
        return try await app.classes.violations(of: matches)
      },
      """,
      sources: ["Sources/App.swift": "class Example {}"]
    )
    let program = try await loadedProgram(in: project)

    let violations = try await #require(program.rules.first).violations()

    #expect(violations.isEmpty)
    #expect(violations.checkedCount == 1)
  }
}
