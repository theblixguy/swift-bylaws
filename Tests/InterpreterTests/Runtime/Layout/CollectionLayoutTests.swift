import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable collection layouts")
struct CollectionLayoutTests {
  @Test("Collection layouts retain the parent condition", arguments: [20, 200])
  func condition(width: Int) async throws {
    let source = "func run() {\n  send(1, 2, values: [3, 4], empty: [])\n}"
    let project = try rulesProject(rules: """
    Rule("arguments") {
      try await app.calls.violations("Arrange arguments") { call in
        let arguments = call.arguments
        let leading = arguments.prefix { $0.label == nil }
        try Layout(arguments, when: !.maximumLineLength(...\(width))) {
          Lines(boundaries: .newline) {
            Joined(leading)
            arguments.dropFirst(leading.count)
          }
        }.applying(toEach: arguments.compactMap { $0.expression?.elements }) {
          Lines($0, boundaries: .newline)
        }
      }
    }
    """, sources: ["Sources/Calls.swift": source])
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    if width == 200 {
      #expect(findings.violations.isEmpty)
    } else {
      let fix = try #require(findings.violations.fixes.first ?? nil)
      #expect(try correctedSource(applying: fix) == """
      func run() {
        send(
          1, 2,
          values: [
            3,
            4
          ],
          empty: []
        )
      }
      """)
    }
  }

  @Test(
    "Stored collection callbacks retain their element type",
    arguments: [false, true], [false, true]
  )
  func callbacks(stored: Bool, throwing: Bool) async throws {
    let body = if throwing {
      "let source = try elements[0].source; return .layout(Lines(elements, boundaries: .newline).layout)"
    } else { ".layout(Lines(elements, boundaries: .newline).layout)" }
    let effects = throwing ? "throws " : ""
    let callback = stored
      ? "let separate = { (elements: [SourceNode]) \(effects)-> LayoutContent<SourceNode> in \(body) }"
      : "func separate(_ elements: [SourceNode]) \(effects)-> LayoutContent<SourceNode> { \(body) }"
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "Sources/Calls.swift": "func run() {\n  send(values: [1, 2], flag: true)\n}",
      "ProjectRules.swift": """
      import Bylaws
      let app = Codebase(root: .automatic(), including: ["Sources/**"])
      \(callback)
      let projectRules: [Rule] = [
        Rule("arguments") {
          try await app.calls.violations("Arrange arguments") { call in
            let collections = call.arguments.compactMap { $0.expression?.elements }
            try Layout(call.arguments, layout: Lines(call.arguments, boundaries: .newline))
              .applying(toEach: collections, separate)
          }
        }
      ]
      """,
    ])
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let fix = try #require(findings.violations.fixes.first ?? nil)

    #expect(try correctedSource(applying: fix) == """
    func run() {
      send(
        values: [
          1,
          2
        ],
        flag: true
      )
    }
    """)
  }

  @Test("Collection callbacks infer automatic policy elements")
  func policies() async throws {
    let project = try rulesProject(rules: """
    Rule("arguments") {
      try await app.calls.violations("Arrange arguments") { call in
        let collections = call.arguments.compactMap { $0.expression?.elements }
        try Layout(call.arguments, layout: Lines(call.arguments, boundaries: .newline))
          .applying(toEach: collections) { elements in
            Group { $0.kind == .syntaxElement }
          }
      }
    }
    """, sources: [
      "Sources/Calls.swift": "func run() {\n  send(values: [1, 2], flag: true)\n}",
    ])
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let fix = try #require(findings.violations.fixes.first ?? nil)

    #expect(try correctedSource(applying: fix) == """
    func run() {
      send(
        values: [1, 2],
        flag: true
      )
    }
    """)
  }

  @Test("Collection callbacks propagate thrown source errors")
  func throwingCallback() async throws {
    let project = try rulesProject(rules: """
    Rule("arguments") {
      try await app.calls.violations("Arrange arguments") { call in
        let collections = call.arguments.compactMap { $0.expression?.elements }
        try Layout(call.arguments, layout: Lines(call.arguments, boundaries: .newline))
          .applying(toEach: collections) { elements in
            let element = try elements.only()
            Lines(elements)
          }
      }
    }
    """, sources: [
      "Sources/Calls.swift": "func run() { send(values: [1, 2], flag: true) }",
    ])
    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)

    await #expect {
      try await rule.findings()
    } throws: { error in
      String(describing: error)
        .contains("Source matches must contain one match, found 2")
    }
  }

  @Test("Collection callbacks reject source from another list")
  func foreignElements() async throws {
    let project = try rulesProject(rules: """
    Rule("arguments") {
      try await app.calls.violations("Arrange arguments") { call in
        let collections = call.arguments.compactMap { $0.expression?.elements }
        try Layout(call.arguments, layout: Lines(call.arguments, boundaries: .newline))
          .applying(toEach: collections) { elements in
            Lines(collections[0], boundaries: .newline)
          }
      }
    }
    """, sources: [
      "Sources/Calls.swift": "func run() { send(first: [1, 2], second: [3, 4]) }",
    ])
    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)

    await #expect {
      try await rule.findings()
    } throws: { error in
      String(describing: error)
        .contains("SourceLayout must emit elements from its input collection")
    }
  }

  @Test("Collection layouts reject incompatible inputs", arguments: [
    (
      ".applying(toEach: call.arguments) { Lines($0) }",
      "applying takes collections of captured source"
    ),
    (
      ".applying(toEach: [1, 2]) { Lines($0) }",
      "applying takes collections of captured source"
    ),
    (
      ".applying(toEach: [[1, 2]]) { Lines($0) }",
      "applying takes collections of captured source"
    ),
    (
      ".applying(toEach: collections) { (elements: [Attribute]) in Lines(elements) }",
      "the closure parameter must be"
    ),
    (
      ".applying(toEach: collections) { elements in return Group<SourceNode> { true } }",
      "the closure must be LayoutContent<SourceNode>"
    ),
  ])
  func rejected(expression: String, message: String) async throws {
    let project = try correctionProject(ruleBody: """
    try await app.calls.violations("Arrange arguments") { call in
      let collections = call.arguments.compactMap { $0.expression?.elements }
      try Layout(call.arguments, layout: Lines(call.arguments))\(expression)
    }
    """)
    let program = await RuleProgram.loaded(
      fromFiles: ["\(project.rootURL.path)/ProjectRules.swift"]
    )

    #expect(
      program.diagnostics.contains { $0.message.contains(message) },
      "\(program.diagnostics.map(\.message))"
    )
  }
}
