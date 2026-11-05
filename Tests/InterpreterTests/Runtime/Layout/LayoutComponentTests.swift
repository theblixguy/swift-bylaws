import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Testing

@Suite("Portable layout components")
struct LayoutComponentTests {
  @Test("Direct components compose with stored layouts", arguments: [
    "Line(declaration.attributes)",
    "Wrap(declaration.attributes, width: 80)",
    "Align(layout: Line(declaration.attributes))",
    "Indent(layout: Line(declaration.attributes))",
    "SourceLayout(Line(declaration.attributes))",
    "LayoutContent<Attribute>.layout(Line(declaration.attributes))",
  ])
  func components(layout: String) async throws {
    let project = try rulesProject(rules: """
    Rule("attributes") {
      try await app.classes.violations("Put attributes on one line") { declaration in
        try Layout(declaration.attributes, layout: \(layout))
      }
    }
    """, sources: [
      "Sources/Store.swift": "@MainActor\n@Observable\nclass Store {}",
    ])
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let fix = try #require(findings.violations.fixes.first ?? nil)

    #expect(try correctedSource(applying: fix) ==
      "@MainActor @Observable\nclass Store {}")
  }

  @Test(
    "Contained collection corrections match builder and value forms",
    arguments: [true, false]
  )
  func applying(builder: Bool) async throws {
    let child = "try Layout(elements, layout: Lines(elements, boundaries: .newline))"
    let changes = builder ? "{ \(child) }" : "(\(child))"
    let source = "func run() {\n  send(values: [1, 2], mode: 3)\n}"
    let project = try rulesProject(rules: """
    Rule("arguments") {
      try await app.calls.violations("Put arguments on separate lines") { call in
        let collections = call.arguments.compactMap { $0.expression?.elements }
        let elements = collections[0]
        try Layout(call.arguments, layout: Lines(call.arguments, boundaries: .newline)).applying \(changes)
      }
    }
    """, sources: ["Sources/Calls.swift": source])
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let fix = try #require(findings.violations.fixes.first ?? nil)

    #expect(try correctedSource(applying: fix) ==
      "func run() {\n  send(\n    values: [\n      1,\n      2\n    ],\n    mode: 3\n  )\n}")
  }

  @Test("Collection elements keep dictionary pairs and empty arrays")
  func elements() async throws {
    let project = try rulesProject(rules: """
    Rule("collections") {
      try await app.calls.violations("Expand collections") { call in
        try Layout(call.arguments, layout: Lines(call.arguments, boundaries: .newline)).applying {
          for elements in call.arguments.compactMap({ $0.expression?.elements }) {
            try Layout(elements, layout: Lines(elements, boundaries: .newline))
          }
        }
      }
    }
    """, sources: [
      "Sources/Calls.swift": "func run() {\n  send(values: [\"a\": 1, \"b\": 2], empty: [], flag: true)\n}",
    ])
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let fix = try #require(findings.violations.fixes.first ?? nil)

    #expect(try correctedSource(applying: fix) ==
      "func run() {\n  send(\n    values: [\n      \"a\": 1,\n      \"b\": 2\n    ],\n    empty: [],\n    flag: true\n  )\n}")
  }

  @Test("Only layouts take contained corrections", arguments: [
    "try Replace(call, with: call).applying { SourceCorrection.satisfied }",
    "try Unwrap(call).applying { SourceCorrection.satisfied }",
  ])
  func applyingReceiver(expression: String) async throws {
    let project = try correctionProject(ruleBody: """
    try await app.calls.violations("Update calls") { call in
      \(expression)
    }
    """)

    await expectCorrectionRejection(
      in: project,
      containing: "'applying' is not a supported member",
      atLine: 6
    )
  }

  @Test("Component arguments retain native labels", arguments: [
    "Line(layout: { call.arguments })", "Wrap(width: 80, call.arguments)",
    "Lines(boundaries: .newline, call.arguments)",
  ])
  func componentLabels(component: String) async throws {
    let project = try correctionProject(ruleBody: """
    try await app.calls.violations("Separate arguments") { call in
      try Layout(call.arguments, layout: \(component))
    }
    """)

    await expectCorrectionRejection(
      in: project,
      containing: "takes source elements",
      atLine: 6
    )
  }

  @Test(
    "Boundaries reject whitespace outside Lines",
    arguments: [".blankLine", ".space", "true"]
  )
  func boundaries(value: String) async throws {
    let project = try correctionProject(ruleBody: """
    try await app.calls.violations("Separate arguments") { call in
      try Layout(call.arguments, layout: Lines(call.arguments, boundaries: \(value)))
    }
    """)

    await expectCorrectionRejection(
      in: project,
      containing: "the boundaries",
      atLine: 6
    )
  }
}
