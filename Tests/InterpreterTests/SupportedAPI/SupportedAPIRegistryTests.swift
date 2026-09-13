import BylawsInterpreter
import BylawsTestSupport
import Foundation
import Testing

@Suite("Supported interpreted API")
struct SupportedAPIRegistryTests {
  @Test("Each identifier and name has one registry entry")
  func entriesAreCompleteAndUnique() {
    let queryNames = SupportedAPI.queries.map(\.name)
    let filterNames = SupportedAPI.filters.map(\.name)
    let matcherNames = SupportedAPI.matchers.map(\.name)
    let queryIDs = SupportedAPI.queries.map(\.id)
    let filterIDs = SupportedAPI.filters.map(\.id)
    let matcherIDs = SupportedAPI.matchers.map(\.id)

    #expect(
      Set(queryIDs) == Set(SupportedAPI.Query.ID.allCases)
    )
    #expect(
      Set(filterIDs) == Set(SupportedAPI.Filter.ID.allCases)
    )
    #expect(
      Set(matcherIDs) == Set(SupportedAPI.Matcher.ID.allCases)
    )
    #expect(Set(queryIDs).count == queryIDs.count)
    #expect(Set(filterIDs).count == filterIDs.count)
    #expect(Set(matcherIDs).count == matcherIDs.count)
    #expect(Set(queryNames).count == queryNames.count)
    #expect(Set(filterNames).count == filterNames.count)
    #expect(Set(matcherNames).count == matcherNames.count)
    #expect(
      Set(SupportedAPI.queries.map(\.declarationFamily))
        == Set(SupportedAPI.DeclarationFamily.allCases)
    )
    #expect(
      SupportedAPI.matchers.allSatisfy {
        !$0.declarationFamilies.isEmpty
      }
    )
  }

  @Test("Every runtime member has one contract for each receiver")
  func runtimeEntriesAreCompleteAndUnique() {
    let entries = SupportedAPI.runtimeMembers.map { entry in
      entry.receivers.map { receiver in
        let kind = switch entry.kind {
        case .property: "property"
        case .method: "method"
        }
        return (receiver, entry.name, kind)
      }
    }.flatMap(\.self)
    let keys = entries.map { "\($0.0):\($0.1.rawValue):\($0.2)" }

    #expect(Set(keys).count == keys.count)
    #expect(
      Set(SupportedAPI.runtimeMembers.map(\.name))
        == Set(SupportedAPI.Member.allCases)
    )
    #expect(
      Set(
        SupportedAPI.runtimeMembers.compactMap { entry in
          guard case let .method(call) = entry.kind else { return nil }
          return call.method
        }
      ) == Set(SupportedAPI.Method.allCases)
    )
  }

  @Test("The CLI capability table matches the runtime registry")
  func capabilityTableMatchesRegistry() throws {
    let repository = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let article = try String(
      contentsOf: repository.appending(
        path: "Sources/Bylaws/Bylaws.docc/RunningRulesFromTheCLI.md"
      ),
      encoding: .utf8
    )
    let start = "<!-- runtime-capabilities:start -->"
    let end = "<!-- runtime-capabilities:end -->"
    let startRange = try #require(article.range(of: start))
    let endRange = try #require(
      article.range(of: end, range: startRange.upperBound..<article.endIndex)
    )
    let generated = article[startRange.upperBound..<endRange.lowerBound]
      .trimmingCharacters(in: .whitespacesAndNewlines)

    #expect(
      generated == SupportedAPI.runtimeCapabilityMarkdown,
      "\n\(SupportedAPI.runtimeCapabilityMarkdown)"
    )
  }

  @Test("Every registered matcher has an adapter for each declaration family")
  func matcherAdaptersCoverTheRegistry() async throws {
    let rules = try Self.registeredMatcherRules()
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      \(rules.joined(separator: "\n"))
      """,
      "Sources/App.swift": "struct App {}",
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)

    #expect(program.errors.isEmpty)
    #expect(program.rules.count == rules.count)
  }

  @Test("Every registered filter compiles from its argument contract")
  func filterAdaptersCoverTheRegistry() async throws {
    var rules: [String] = []
    for filter in SupportedAPI.filters {
      for declarationFamily in filter.declarationFamilies.sorted(
        by: { $0.rawValue < $1.rawValue }
      ) {
        let query = try #require(
          SupportedAPI.queries.first {
            $0.declarationFamily == declarationFamily
          }
        )
        let matcher = try #require(
          SupportedAPI.matchers.first {
            $0.declarationFamilies.contains(declarationFamily)
          }
        )
        let index = rules.count
        rules.append(
          """
          Rule("filter-\(index)", "Filter \(index)") {
            app.\(query.name).\(filter.name)\(Self
            .arguments(for: filter.arguments))
              .violations(
                of: .\(matcher.name)\(Self.arguments(for: matcher.arguments))
              )
          }
          """
        )
      }
    }
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      \(rules.joined(separator: "\n"))
      """,
      "Sources/App.swift": "struct App {}",
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)

    #expect(program.errors.isEmpty)
    #expect(program.rules.count == rules.count)
  }

  private static func registeredMatcherRules() throws -> [String] {
    var rules: [String] = []
    for matcher in SupportedAPI.matchers {
      for declarationFamily in matcher.declarationFamilies.sorted(
        by: { $0.rawValue < $1.rawValue }
      ) {
        let query = try #require(
          SupportedAPI.queries.first {
            $0.declarationFamily == declarationFamily
          }
        )
        let index = rules.count
        rules.append(
          """
          Rule("matcher-\(index)", "Matcher \(index)") {
            app.\(query.name).violations(
              of: .\(matcher.name)\(arguments(for: matcher.arguments))
            )
          }
          """
        )
      }
    }
    return rules
  }

  private static func arguments(
    for contract: SupportedAPI.ArgumentContract
  ) -> String {
    switch contract {
    case .none:
      ""
    case let .strings(startingWith: label):
      "(\(label.map { "\($0.rawValue): " } ?? "")\"Value\")"
    case let .oneString(labelled: label):
      "(\(label.map { "\($0.rawValue): " } ?? "")\"Value\")"
    case let .optionalStringArray(labelled: label):
      "(\(label.rawValue): [\"Value\"])"
    case .functionParameter:
      "(typed: \"Value\")"
    case .visibility:
      "(atLeast: .public)"
    }
  }
}
