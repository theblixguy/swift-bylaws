import BylawsCore
import BylawsInterpreter
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable layout value contracts")
struct LayoutValueParityTests {
  @Test(
    "Explicit layout content stays distinct from separators",
    arguments: [false, true]
  )
  func contentCases(explicit: Bool) async throws {
    let component = explicit ? ".layout(.newline)" : ".separator(.newline)"
    let project = try rulesProject(rules: """
    Rule("attributes") {
      try await app.classes.violations("Arrange attributes") { declaration in
        let content: LayoutContent<Attribute> = .sequence([
          .group(Group { _ in true }),
          \(component)
        ])
        try Layout(declaration.attributes, layout: content)
      }
    }
    """, sources: ["Sources/Item.swift": "@A @B class Item {}"])
    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)

    if explicit {
      await #expect {
        try await rule.findings()
      } throws: { error in
        String(describing: error)
          .contains("Layout must use explicit source or automatic policies")
      }
    } else {
      #expect(try await rule.findings().violations.isEmpty)
    }
  }

  @Test("Layouts take edit arrays and nested correction arrays", arguments: [
    "edits", "[edits]", "changes", "[changes]",
  ], [false, true])
  func correctionArrays(expression: String, wrapped: Bool) async throws {
    let value = wrapped ? "SourceLayout { \(expression) }" : expression
    let project = try rulesProject(rules: """
    Rule("attributes") {
      try await app.classes.violations("Replace attributes") { declaration in
        let attributes = declaration.attributes
        let edits = [
          try attributes[0].source.replacement(with: "@C"),
          try attributes[1].source.replacement(with: "@D")
        ]
        let changes = [SourceCorrection(edits: edits)]
        try Layout(attributes) {
          \(value)
        }
      }
    }
    """, sources: ["Sources/Item.swift": "@A @B class Item {}"])
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let fix = try #require(findings.violations.fixes.first ?? nil)

    #expect(try correctedSource(applying: fix) == "@C @D class Item {}")
  }
}

extension LayoutValueParityTests {
  @Test(
    "Stored layout content retains its selected element type",
    arguments: [false, true], [false, true]
  )
  func selectedContent(contained: Bool, matching: Bool) async throws {
    let selected = contained ? "SourceNode" : "FunctionCall.Argument"
    let element = matching ? selected : "Attribute"
    let body = """
    let content: LayoutContent<\(element)> = .layout(Lines(elements, boundaries: .newline).layout)
    content
    """
    let correction = if contained {
      """
      let collections = call.arguments.compactMap { $0.expression?.elements }
      try Layout(call.arguments, layout: Lines(call.arguments, boundaries: .newline))
        .applying(toEach: collections) { elements in
          \(body)
        }
      """
    } else {
      """
      let elements = call.arguments
      try Layout(elements) {
        \(body)
      }
      """
    }
    let project = try rulesProject(rules: """
    Rule("arguments") {
      try await app.calls.violations("Arrange arguments") { call in
        \(correction)
      }
    }
    """, sources: [
      "Sources/Calls.swift": "func run() {\n  send(values: [1, 2], flag: true)\n}",
    ])
    let program = await RuleProgram.loaded(
      fromFiles: [project.fileURL(for: "ProjectRules.swift").path]
    )

    if matching {
      try program.requireNoDiagnostics()
      let findings = try await #require(program.rules.first).findings()
      let fix = try #require(findings.violations.fixes.first ?? nil)
      let output = try correctedSource(applying: fix)
      #expect(output.contains("send(\n    values:"))
      #expect(output
        .contains(contained ? "values: [\n      1,\n      2\n    ]" :
          "values: [1, 2]"))
    } else {
      #expect(
        program.diagnostics.contains {
          $0.message
            .contains("the layout element must be \(selected), not Attribute")
        },
        "\(program.diagnostics.map(\.message))"
      )
    }
  }
}
