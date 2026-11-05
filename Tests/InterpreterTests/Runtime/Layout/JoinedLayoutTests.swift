import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable joined layouts")
struct JoinedLayoutTests {
  @Test("Joined elements share one outer list item", arguments: [
    "Joined(leading)", "Joined { leading }",
    "Joined(layout: SourceLayout(leading))",
  ])
  func joined(component: String) async throws {
    let project = try rulesProject(rules: """
    Rule("arguments") {
      try await app.calls.violations("Arrange arguments") { call in
        let arguments = call.arguments
        let leading = arguments.prefix { $0.label == nil }
        try Layout(arguments) {
          Lines(boundaries: .newline) {
            \(component)
            arguments.dropFirst(leading.count)
          }
        }
      }
    }
    """, sources: [
      "Sources/Calls.swift": "func run() {\n  send(1, 2, mode: 3, values: [4, 5])\n}",
    ])
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let fix = try #require(findings.violations.fixes.first ?? nil)

    #expect(try correctedSource(applying: fix) == """
    func run() {
      send(
        1, 2,
        mode: 3,
        values: [4, 5]
      )
    }
    """)
  }

  @Test("Empty joined groups add no separators")
  func emptyJoined() async throws {
    let project = try rulesProject(rules: """
    Rule("arguments") {
      try await app.calls.violations("Arrange arguments") { call in
        let arguments = call.arguments
        try Layout(arguments) {
          Lines(boundaries: .newline) {
            Joined(arguments.prefix(0))
            arguments
          }
        }
      }
    }
    """, sources: [
      "Sources/Calls.swift": "func run() {\n  send(first: 1, second: 2)\n}",
    ])
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let fix = try #require(findings.violations.fixes.first ?? nil)

    #expect(try correctedSource(applying: fix) == """
    func run() {
      send(
        first: 1,
        second: 2
      )
    }
    """)
  }

  @Test("Joined elements retain contained multiline layouts")
  func multilineJoined() async throws {
    let project = try rulesProject(rules: """
    Rule("arguments") {
      try await app.calls.violations("Arrange arguments") { call in
        let arguments = call.arguments
        let leading = arguments.prefix { $0.label == nil }
        try Layout(arguments) {
          Lines(boundaries: .newline) {
            Joined(leading)
            arguments.dropFirst(leading.count)
          }
        }.applying(toEach: arguments.compactMap { $0.expression?.elements }) {
          Lines($0, boundaries: .newline)
        }
      }
    }
    """, sources: [
      "Sources/Calls.swift": "func run() {\n  send([1, 2], 3, mode: 4)\n}",
    ])
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let fix = try #require(findings.violations.fixes.first ?? nil)

    #expect(try correctedSource(applying: fix) == """
    func run() {
      send(
        [
          1,
          2
        ], 3,
        mode: 4
      )
    }
    """)
  }

  @Test("Joined builders reject automatic policies", arguments: [
    "Joined { Group<Attribute> { true } }",
    "Joined(layout: Group<Attribute> { true })",
  ])
  func policies(component: String) async throws {
    let project = try correctionProject(ruleBody: """
    try await app.calls.violations("Arrange arguments") { call in
      try Layout(call.arguments, layout: \(component))
    }
    """)
    let program = await RuleProgram.loaded(
      fromFiles: ["\(project.rootURL.path)/ProjectRules.swift"]
    )

    #expect(program.diagnostics.contains {
      $0.message.contains("SourceLayout takes source values")
        || $0.message.contains("Joined takes source elements")
    }, "\(program.diagnostics.map(\.message))")
  }
}
