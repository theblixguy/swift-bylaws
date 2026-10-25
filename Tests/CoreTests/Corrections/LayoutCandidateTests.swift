import Bylaws
import BylawsCore
import Foundation
import Testing

@Suite("Unchanged layout context")
struct LayoutCandidateTests {
  @Test("Passing layouts retain policy without reporting violations")
  func passingLayout() async throws {
    let violations = try await passingViolations()
    let candidate = try #require(violations.layoutCandidates.first)

    #expect(violations.checkedCount == 1)
    #expect(violations.offenders.isEmpty)
    #expect(violations.fixes.isEmpty)
    #expect(violations.layoutCandidates.count == 1)
    #expect(candidate.layout != nil)
    #expect(candidate.source.text == "@Observable @MainActor\n")
    #expect(candidate.replacement == "@Observable @MainActor\n")
  }

  @Test("Changed fixes and passing layout context stay separate")
  func mixedLayouts() async throws {
    let codebase = Codebase(root: .sources([
      "Sources/Screen.swift": "@MainActor @Observable class Changed {}\n@Observable @MainActor\nclass Passing {}",
    ]))
    let violations = try await codebase.classes
      .violations("Order attributes") { declaration in
        try declaration.attributes.replacement {
          Line { declaration.attributes.sorted { $0.name > $1.name } }
        }
      }
    let candidate = try #require(violations.layoutCandidates.first)
    let fix = try #require(violations.fixes.first ?? nil)
    let edit = try #require(fix.edits.first)

    #expect(violations.checkedCount == 2)
    #expect(violations.offenders.map(\.name) == ["Changed"])
    #expect(violations.fixes.count == 1)
    #expect(violations.layoutCandidates.count == 1)
    #expect(edit.source.text == "@MainActor @Observable ")
    #expect(edit.replacement == "@Observable @MainActor\n")
    #expect(candidate.source.text == "\n@Observable @MainActor\n")
    #expect(candidate.replacement == "\n@Observable @MainActor\n")
  }

  @Test("Erasure filtering builders and combined checks retain layout context")
  func propagation() async throws {
    let original = try await passingViolations()
    let candidate = try #require(original.layoutCandidates.first)
    let erased = original.erased()
    let filtered = erased.filteringOffenders { _ in false }
    let rebuilt = try await filtered.withFix { _ in }
    let combined = Rule.Findings(checks: [
      rebuilt,
      Violations<Offender>(rule: "empty check", offenders: [], checkedCount: 0),
    ]).violations

    #expect(erased.layoutCandidates == [candidate])
    #expect(filtered.layoutCandidates == [candidate])
    #expect(rebuilt.layoutCandidates == [candidate])
    #expect(combined.layoutCandidates == [candidate])
    #expect(combined.checkedCount == 1)
    #expect(combined.isEmpty)
  }

  @Test("Standalone violation transport preserves passing layout context")
  func transport() async throws {
    let original = try await passingViolations().erased()
    let decoded = try JSONDecoder().decode(
      Violations<Offender>.self, from: JSONEncoder().encode(original)
    )

    #expect(decoded.checkedCount == 1)
    #expect(decoded.isEmpty)
    #expect(decoded.layoutCandidates.count == 1)
    #expect(decoded.layoutCandidates.first?
      .replacement == "@Observable @MainActor\n")
    #expect(decoded == original)
  }

  @Test(
    "Layout context rejects changed or unplanned candidates",
    arguments: [false, true]
  )
  func malformedCandidates(changed: Bool) async throws {
    let original = try await passingViolations()
    let candidate = try #require(original.layoutCandidates.first)
    let malformed = if changed {
      SourceFix.Edit(
        source: candidate.source, replacement: "@MainActor\n",
        layout: candidate.layout
      )
    } else {
      candidate.source.replacement(with: candidate.source.text)
    }
    let violations = Violations<Offender>(
      rule: "retain layout", offenders: [], checkedCount: 1, witnesses: [],
      layoutCandidates: [malformed]
    )

    let error = try #require(throws: SourceLayoutComposition.Failure.self) {
      try JSONEncoder().encode(violations)
    }
    #expect(error
      .description ==
      "SourceLayout context must preserve the original bytes. Report a changed layout as a correction.")
  }

  @Test("Composition rejects changed policy supplied as context")
  func changedContext() async throws {
    let codebase = Codebase(root: .sources([
      "Sources/Screen.swift": "@MainActor @Observable class Screen {}",
    ]))
    let declaration = try await codebase.classes.only()
    let attributes = declaration.attributes
    let changed = try attributes.replacement { Line { attributes.reversed() } }
    let first = try #require(attributes.first)
    let active = try first.source.slice(1..<10).replacement(with: "Worker")

    let error = try #require(throws: SourceLayoutComposition.Failure.self) {
      try SourceLayoutComposition.compose(
        edits: [active],
        candidates: [changed]
      )
    }
    #expect(error
      .description ==
      "SourceLayout context must preserve the original bytes. Report a changed layout as a correction.")
  }

  @Test("Parent indentation activates unchanged child width policy")
  func parentPlacement() async throws {
    let codebase = Codebase(root: .sources([
      "Sources/Calls.swift": "func run() {\n  pair(first: 1, second: 2)\n}",
    ]))
    let child = try await codebase.calls.violations("Wrap long calls") { call in
      try call.arguments.replacement(whenLineExceeds: 27) {
        for argument in call.arguments {
          Newline()
          argument
        }
        Newline()
      }
    }
    let parent = try await codebase.syntaxNodes(of: .codeBlock)
      .violations("Indent statements") { block in
        try block.statements.replacement {
          Indent {
            Newline()
            block.statements
          }
          Newline()
        }
      }
    let candidate = try #require(child.layoutCandidates.first)
    let fix = try #require(parent.fixes.first ?? nil)
    let source = try #require(fix.edits.first).source.file
    let corrected = try source.replacement(
      applying: fix.edits, layoutCandidates: child.layoutCandidates
    )

    #expect(child.checkedCount == 1)
    #expect(child.isEmpty)
    #expect(child.layoutCandidates.count == 1)
    #expect(candidate.replacement == "first: 1, second: 2")
    #expect(parent.checkedCount == 1)
    #expect(parent.count == 1)
    #expect(corrected.replacement == """
    func run() {
        pair(
          first: 1,
          second: 2
        )
    }
    """)
  }

  @Test("Changed child activates unchanged parent width policy")
  func childWidth() async throws {
    let codebase = Codebase(root: .sources([
      "Sources/Calls.swift": "let result = pair(1, 2)",
    ]))
    let passing = try await codebase.calls
      .violations("Wrap long calls") { call in
        try call.arguments.replacement(whenLineExceeds: 23) {
          for argument in call.arguments {
            Newline()
            argument
          }
          Newline()
        }
      }
    let candidate = try #require(passing.layoutCandidates.first)
    let call = try await codebase.calls.only()
    let argument = try #require(call.arguments.first)
    let active = try argument.expressionSource.replacement(with: "100000000")

    let corrected = try candidate.source.file.replacement(
      applying: [active], layoutCandidates: passing.layoutCandidates
    )

    #expect(passing.checkedCount == 1)
    #expect(passing.isEmpty)
    #expect(passing.layoutCandidates.count == 1)
    #expect(candidate.replacement == "1, 2")
    #expect(corrected.replacement == """
    let result = pair(
      100000000,
      2
    )
    """)
  }

  @Test("Same-line changes activate dormant width policy", arguments: [
    (
      "send(1, 2)", 10, "send", "sendWithLongName",
      "sendWithLongName(\n  1,\n  2\n)"
    ),
    (
      "send(1, 2).id", 13, "id", "longIdentifier",
      "send(\n  1,\n  2\n).longIdentifier"
    ),
    (
      "let prefix = 1\nsend(1, 2)", 10, "\n", "; ",
      "let prefix = 1; send(\n  1,\n  2\n)"
    ),
  ])
  func sameLineChange(
    source: String, maximumWidth: Int, match: String,
    replacement: String, expected: String
  ) async throws {
    let codebase = Codebase(root: .sources(["Sources/Calls.swift": source]))
    let passing = try await codebase.syntaxNodes(of: .functionCall)
      .violations("Wrap long calls") { node in
        if let call = node.call {
          try call.arguments.replacement(whenLineExceeds: maximumWidth) {
            for argument in call.arguments {
              Newline()
              argument
            }
            Newline()
          }
        }
      }
    let candidate = try #require(passing.layoutCandidates.first)
    let region = try candidate.source.file.matches(of: /[A-Za-z]+|\n/)
      .filter { $0.text == match }.only()
    let active = region.replacement(with: replacement)

    let corrected = try candidate.source.file.replacement(
      applying: [active], layoutCandidates: passing.layoutCandidates
    )

    #expect(passing.checkedCount == 1)
    #expect(passing.isEmpty)
    #expect(passing.layoutCandidates.count == 1)
    #expect(candidate.replacement == "1, 2")
    #expect(corrected.replacement == expected)
  }

  @Test(
    "Line-end insertions activate width policy on their physical line",
    arguments: [
      ("send(1, 2)", 10, "send(\n  1,\n  2\n).id"),
      ("send(1, 2)\n", 10, "send(\n  1,\n  2\n).id\n"),
      ("send(1, 2)\r\n", 10, "send(\r\n  1,\r\n  2\r\n).id\r\n"),
      ("send(1, 2)\r", 10, "send(\r  1,\r  2\r).id\r"),
      ("send(1, 2)\n", 11, "send(1, 2)\n.id"),
      ("send(1, 2)\r\n", 12, "send(1, 2)\r\n.id"),
      ("send(1, 2)\r", 11, "send(1, 2)\r.id"),
    ]
  )
  func lineEndInsertion(
    source: String, offset: Int, expected: String
  ) async throws {
    let codebase = Codebase(root: .sources(["Sources/Calls.swift": source]))
    let passing = try await codebase.syntaxNodes(of: .functionCall)
      .violations("Wrap long calls") { node in
        if let call = node.call {
          try call.arguments.replacement(whenLineExceeds: 10) {
            for argument in call.arguments {
              Newline()
              argument
            }
            Newline()
          }
        }
      }
    let candidate = try #require(passing.layoutCandidates.first)
    let insertion = try candidate.source.file.slice(offset..<offset)
      .replacement(with: ".id")

    let corrected = try candidate.source.file.replacement(
      applying: [insertion], layoutCandidates: passing.layoutCandidates
    )

    #expect(passing.checkedCount == 1)
    #expect(passing.isEmpty)
    #expect(passing.layoutCandidates.count == 1)
    #expect(candidate.replacement == "1, 2")
    #expect(corrected.replacement.utf8.elementsEqual(expected.utf8))
  }

  private func passingViolations() async throws -> Violations<Class> {
    let codebase = Codebase(root: .sources([
      "Sources/Screen.swift": "@Observable @MainActor\nclass Screen {}",
    ]))
    return try await codebase.classes
      .violations("Keep attribute order") { declaration in
        try declaration.nameSource.replacement(with: declaration.name)
        try declaration.attributes
          .replacement { Line { declaration.attributes } }
      }
  }
}
