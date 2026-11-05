import Bylaws
import BylawsCore
import Foundation
import Testing

@Suite("Attached layout corrections")
struct AttachedLayoutTests {
  @Test("Correct parent layout retains contained changes")
  func satisfiedParent() async throws {
    let app = Codebase(root: .sources([
      "Sources/Calls.swift": """
      let result = send(
        values: [1, 2],
        option: true
      )
      """,
    ]))
    let call = try #require(await app.calls.first)
    let elements = try #require(call.arguments.first?.expression?.elements)
    let layout = try Layout(
      call.arguments,
      layout: Lines(call.arguments, boundaries: .newline)
    )
    let operation = try layout.applying {
      try Layout(elements, layout: Lines(elements, boundaries: .newline))
    }

    #expect(layout.correction.outcome == .satisfied)
    #expect(operation.correction.outcome == .violation)
    #expect(try applying(operation) == """
    let result = send(
      values: [
        1,
        2
      ],
      option: true
    )
    """)
  }

  @Test("Contained value corrections preserve one parent occurrence")
  func storedChanges() async throws {
    let app = Codebase(root: .sources([
      "Sources/Calls.swift": "let result = send(values: [1, 2], option: true)",
    ]))
    let call = try #require(await app.calls.first)
    let elements = try #require(call.arguments.first?.expression?.arrayElements)
    let changes = try [
      Replace(elements[0], with: "3"),
      Replace(elements[1], with: "4"),
    ]
    let operation = try Layout(
      call.arguments,
      layout: Lines(call.arguments, boundaries: .newline)
    )
    .applying(changes)

    #expect(try applying(operation) == """
    let result = send(
      values: [3, 4],
      option: true
    )
    """)
  }

  @Test("Parent width condition controls contained changes")
  func inactiveParent() async throws {
    let app = Codebase(root: .sources([
      "Sources/Calls.swift": "let result = send(values: [1, 2], option: true)",
    ]))
    let call = try #require(await app.calls.first)
    let elements = try #require(call.arguments.first?.expression?.elements)
    let operation = try Layout(
      call.arguments, layout: Lines(call.arguments, boundaries: .newline),
      when: .maximumLineLength(101...)
    ).applying {
      try Layout(elements, layout: Lines(elements, boundaries: .newline))
    }

    #expect(operation.correction.outcome == .satisfied)
    #expect(operation.correction.fix?.edits.isEmpty == true)
    #expect(operation.correction.fix?.layoutCandidates.count == 1)
  }

  @Test("Empty contained layouts retain their parent arguments")
  func emptyChildren() async throws {
    let app = Codebase(root: .sources([
      "Sources/Calls.swift": "let result = send(values: [], lookup: [:])",
    ]))
    let call = try #require(await app.calls.first)
    let operation = try Layout(
      call.arguments,
      layout: Lines(call.arguments, boundaries: .newline)
    )
    .applying {
      for elements in call.arguments.compactMap({ $0.expression?.elements }) {
        try Layout(elements, layout: Lines(elements, boundaries: .newline))
      }
    }

    #expect(try applying(operation) == """
    let result = send(
      values: [],
      lookup: [:]
    )
    """)
  }

  @Test("Unknown attachment takes precedence over unavailable layout")
  func unknownAttachment() async throws {
    let app = Codebase(root: .sources([
      "Sources/Calls.swift": "let result = send(first: 1, second: 2)",
    ]))
    let call = try #require(await app.calls.first)
    let operation = try Layout(call.arguments) {
      SourceCorrection.unavailable("Keep the attached comment.")
    }.applying {
      SourceCorrection.undetermined("Check the called declaration.")
    }

    #expect(operation.correction.outcome == .undetermined)
    #expect(operation.correction.reason == "Check the called declaration.")
  }

  @Test("Attached changes retain ownership through encoding")
  func encodedAttachment() async throws {
    let app = Codebase(root: .sources([
      "Sources/Calls.swift": "let result = send(values: [1, 2], option: true)",
    ]))
    let call = try #require(await app.calls.first)
    let elements = try #require(call.arguments.first?.expression?.elements)
    let operation = try Layout(
      call.arguments,
      layout: Lines(call.arguments, boundaries: .newline)
    )
    .applying {
      try Layout(elements, layout: Lines(elements, boundaries: .newline))
    }
    let fix = try #require(operation.correction.fix)
    let decoded = try JSONDecoder().decode(
      SourceFix.self,
      from: JSONEncoder().encode(fix)
    )

    #expect(try applying(decoded) == """
    let result = send(
      values: [
        1,
        2
      ],
      option: true
    )
    """)
  }

  @Test("Empty parent ignores contained corrections without source validation")
  func emptyParent() throws {
    let empty: [FunctionCall.Argument] = []
    let operation = try Layout(empty, layout: Lines(empty))
      .applying(SourceCorrection.undetermined("Check the called declaration."))

    #expect(operation.correction.outcome == .notApplicable)
    #expect(operation.correction.fix == nil)
  }

  @Test("Independent descendant correction applies below parent width limit")
  func independentChild() async throws {
    let app = Codebase(root: .sources([
      "Sources/Calls.swift": "let result = send(values: [1, 2], option: true)",
    ]))
    let call = try #require(await app.calls.first)
    let expression = try #require(call.arguments.first?.expression)
    let elements = try #require(expression.elements)
    let values = try #require(expression.arrayElements)
    let operation = try Layout(
      call.arguments, layout: Lines(call.arguments, boundaries: .newline),
      when: .maximumLineLength(101...)
    ).applying {
      try Layout(elements, layout: Lines(elements, boundaries: .newline))
    }
    let parent = try #require(operation.correction.fix)
    let independent = try Replace(values[0], with: "3")
    let replacement = try expression.source.file.replacement(
      applying: independent.correction.fix?.edits ?? [],
      layoutCandidates: parent.layoutCandidates
    )

    #expect(replacement.replacement ==
      "let result = send(values: [3, 2], option: true)")
  }

  @Test("Attachments stay inside parent elements")
  func outsideParent() async throws {
    let app = Codebase(root: .sources([
      "Sources/Calls.swift": "let result = send(first: 1, second: 2)\nlet other = 3",
    ]))
    let call = try #require(await app.calls.first)
    let property = try #require(await app.properties.named("other").first)
    let operation = try Layout(
      call.arguments,
      layout: Lines(call.arguments, boundaries: .newline)
    )
    let change = try Replace(property.nameSource, with: "renamed")

    #expect(throws: SourceError.overlappingEdits) {
      try operation.applying(change)
    }
  }

  @Test("Attached corrections use the parent's captured snapshot")
  func foreignSnapshot() async throws {
    let source = "let result = send(first: 1, second: 2)"
    let first = Codebase(root: .sources(["Sources/First.swift": source]))
    let second = Codebase(root: .sources(["Sources/Second.swift": source]))
    let call = try #require(await first.calls.first)
    let otherCall = try #require(await second.calls.first)
    let argument = try #require(otherCall.arguments.first?.expression)
    let operation = try Layout(
      call.arguments,
      layout: Lines(call.arguments, boundaries: .newline)
    )
    let change = try Replace(argument, with: "3")

    #expect(throws: SourceError.differentSnapshots) {
      try operation.applying(change)
    }
  }

  @Test("Grouping attaches corrections to each retained region")
  func groupedRegions() async throws {
    let app = Codebase(root: .sources([
      "Sources/Model.swift": """
      struct Model {
        let b = 1
        let a = 2
        func separate() {}
        let d = 3
        let c = 4
      }
      """,
    ]))
    let declaration = try #require(await app.syntaxNodes(of: .structDeclaration)
      .first)
    let operation = try Layout(declaration.members) {
      Group { $0.property != nil }.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }.applying {
      for property in declaration.members.compactMap(\.property) {
        try Replace(property.nameSource, with: property.name.uppercased())
      }
    }

    #expect(try applying(operation) == """
    struct Model {
      let A = 2
      let B = 1
      func separate() {}
      let C = 4
      let D = 3
    }
    """)
  }

  @Test("Inserted arguments retain parent-controlled attachments")
  func insertion() async throws {
    let app = Codebase(root: .sources([
      "Sources/Calls.swift": "let result = send(values: [1, 2], option: true)",
    ]))
    let call = try #require(await app.calls.first)
    let elements = try #require(call.arguments.first?.expression?.elements)
    let layout = try Layout(
      call.arguments,
      layout: Lines(call.arguments, boundaries: .newline)
    )
    .applying {
      try Layout(elements, layout: Lines(elements, boundaries: .newline))
    }
    let insertion = try Insert("count: 3", into: call.argumentList)
    let correction = SourceCorrection(combining: [
      layout.correction,
      insertion.correction,
    ])

    #expect(try applying(correction) == """
    let result = send(
      values: [
        1,
        2
      ],
      option: true,
      count: 3
    )
    """)
  }

  private func applying(_ operation: some SourceCorrectionProviding) throws
    -> String
  {
    let fix = try #require(operation.correction.fix)
    let source = try #require(fix.edits.first).source.file
    return try source.replacement(applying: fix.edits).replacement
  }
}
