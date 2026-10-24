import BylawsSemantics
import Testing

@Suite("Nested source layouts")
struct SourceLayoutCompositionTests {
  @Test("Separate line joins can create a width violation for the next pass")
  func siblingLineJoin() throws {
    let original = "first(1, 2); second(3,\n  4)"
    let file = try FileCollector.collect(source: original, path: "/App.swift")
    let calls = file.syntaxNodes(of: .functionCall).compactMap(\.call)
    let first = try #require(calls.first { $0.name == "first" })
    let second = try #require(calls.first { $0.name == "second" })
    let candidate = try first.arguments.replacement(whenLineExceeds: 22) {
      for argument in first.arguments {
        Newline()
        argument
      }
      Newline()
    }
    try #require(candidate.source.text == candidate.replacement)
    let joining = try second.arguments.replacement { second.arguments }
    let corrected = try file.source.replacement(
      applying: [joining],
      layoutCandidates: [candidate]
    )

    #expect(corrected.replacement == "first(1, 2); second(3, 4)")
    let updated = try FileCollector.collect(
      source: corrected.replacement,
      path: "/App.swift"
    )
    let remaining = try #require(updated.syntaxNodes(of: .functionCall).first?
      .call)
    #expect(try remaining.source.hasLine(exceeding: 22))
  }

  @Test(
    "Nested calls compose in either proposal order",
    arguments: [false, true]
  )
  func nestedCalls(reversed: Bool) throws {
    let file = try FileCollector.collect(
      source: "let value = outer(first: inner(left: 1, right: 2), second: 3)",
      path: "/App.swift"
    )
    let edits = try file.calls.map { call in
      try call.arguments.replacement {
        for argument in call.arguments {
          Newline()
          argument
        }
        Newline()
      }
    }
    try #require(edits.count == 2)
    let result = try file.source
      .replacement(applying: reversed ? edits.reversed() : edits)

    #expect(result.replacement == """
    let value = outer(
      first: inner(
        left: 1,
        right: 2
      ),
      second: 3
    )
    """)
  }

  @Test("Nested width conditions use the final parent placement")
  func projectedWidth() throws {
    let file = try FileCollector.collect(
      source: "let value = outer(first: inner(left: 1, right: 2), second: \"A medium second value\")",
      path: "/App.swift"
    )
    let edits = try file.calls.map { call in
      try call.arguments.replacement(whenLineExceeds: 60) {
        for argument in call.arguments {
          Newline()
          argument
        }
        Newline()
      }
    }
    try #require(edits.count == 2)
    let result = try file.source.replacement(applying: edits)

    #expect(result.replacement == """
    let value = outer(
      first: inner(left: 1, right: 2),
      second: "A medium second value"
    )
    """)
  }

  @Test(
    "Nested width includes retained suffix and enclosing comma",
    arguments: [
      (33, "", true),
      (34, "", false),
      (42, ".cached()", true),
      (43, ".cached()", false),
    ]
  )
  func enclosingSuffix(
    maximumWidth: Int,
    suffix: String,
    wrapsInner: Bool
  ) throws {
    let file = try FileCollector.collect(
      source: "let value = outer(first: inner(left: 1, right: 2)\(suffix), second: 3)",
      path: "/App.swift"
    )
    let edits = try file.calls.filter { $0.arguments.count > 1 }.map { call in
      try call.arguments.replacement(whenLineExceeds: maximumWidth) {
        for argument in call.arguments {
          Newline()
          argument
        }
        Newline()
      }
    }
    try #require(edits.count == 2)
    let result = try file.source.replacement(applying: edits)
    let inner = if wrapsInner {
      """
      inner(
          left: 1,
          right: 2
        )\(suffix)
      """
    } else {
      "inner(left: 1, right: 2)\(suffix)"
    }

    #expect(result.replacement == """
    let value = outer(
      first: \(inner),
      second: 3
    )
    """)
  }

  @Test(
    "Short multiline calls retain exact bytes",
    arguments: ["\n", "\r\n", "\r"]
  )
  func shortMultiline(ending: String) throws {
    let source = ["let value = pair(", "  first: 1,", "  second: 2", ")"]
      .joined(separator: ending)
    let file = try FileCollector.collect(source: source, path: "/App.swift")
    let call = try #require(file.calls.first)
    let edit = try call.arguments.replacement(whenLineExceeds: 80) {
      Wrap(width: 80) { call.arguments }
    }

    #expect(edit.source.text.utf8.elementsEqual(edit.replacement.utf8))
    #expect(try file.source.replacement(applying: [edit]).replacement == source)
  }

  @Test(
    "Dormant wrapping layouts reject nonpositive widths",
    arguments: [0, -1]
  )
  func dormantWrapWidth(width: Int) throws {
    let file = try FileCollector.collect(
      source: "let value = send(first: 1, second: 2)", path: "/App.swift"
    )
    let arguments = try #require(file.calls.first).arguments
    try #require(arguments.count == 2)

    #expect(throws: SourceLayoutError.widthMustBePositive) {
      try arguments.replacement(whenLineExceeds: 100) {
        Wrap(width: width) { arguments }
      }
    }
  }

  @Test("Raw ancestors and conflicting same-list layouts remain errors")
  func conflicts() throws {
    let file = try FileCollector.collect(
      source: "let value = outer(first: inner(left: 1, right: 2), second: 3)",
      path: "/App.swift"
    )
    let outer = try #require(file.calls.first { $0.name == "outer" })
    let inner = try #require(file.calls.first { $0.name == "inner" })
    let innerLayout = try inner.arguments.replacement {
      for argument in inner.arguments {
        Newline()
        argument
      }
      Newline()
    }
    #expect(throws: SourceError.overlappingEdits) {
      try file.source.replacement(applying: [
        outer.source.replacement(with: "other()"), innerLayout,
      ])
    }
    let oneLine = try outer.arguments.replacement { outer.arguments }
    let lines = try outer.arguments.replacement {
      for argument in outer.arguments {
        Newline()
        argument
      }
      Newline()
    }
    #expect(throws: SourceError.overlappingEdits) {
      try file.source.replacement(applying: [oneLine, lines])
    }
  }
}
