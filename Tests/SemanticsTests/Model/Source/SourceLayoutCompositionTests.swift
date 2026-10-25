import BylawsSemantics
import Testing

@Suite("Nested source layouts")
struct SourceLayoutCompositionTests {
  @Test(
    "Empty embedded edit retains surrounding argument content",
    arguments: [false, true]
  )
  func partialDeletion(lines: Bool) throws {
    let file = try FileCollector.collect(
      source: "let r = send(first: value!, second: 2)", path: "/App.swift"
    )
    let arguments = try #require(file.calls.first).arguments
    try #require(arguments.count == 2)
    let marker = try arguments[0].source.matches(of: /!/).only()
    let deletion = marker.replacement(with: "")
    let layout = try arguments.replacement {
      if lines {
        Line { deletion }
        Line { arguments[1] }
      } else {
        deletion
        arguments[1]
      }
    }

    let result = try file.source.replacement(applying: [layout])
    let expected = if lines {
      "let r = send(\n  first: value,\n  second: 2\n)"
    } else {
      "let r = send(first: value, second: 2)"
    }

    #expect(result.replacement == expected)
  }

  @Test(
    "Attribute width excludes following declaration line",
    arguments: ["\n", "\r\n", "\r"]
  )
  func followingLine(ending: String) throws {
    let original = "@A @B\(ending)class VeryLongDeclaration {}"
    let file = try FileCollector.collect(source: original, path: "/App.swift")
    let declaration = try #require(file.classes.first)
    try #require(declaration.attributes.count == 2)
    let candidate = try declaration.attributes
      .replacement(whenLineExceeds: 10) {
        for attribute in declaration.attributes {
          Line { attribute }
        }
      }
    try #require(candidate.source.text == "@A @B\(ending)")
    #expect(candidate.replacement == "@A @B\(ending)")

    let unchanged = try file.source.replacement(applying: [candidate])
    #expect(unchanged.replacement == original)
    let rename = try declaration.nameSource
      .replacement(with: "AnotherVeryLongDeclaration")
    let renamed = try file.source.replacement(applying: [candidate, rename])

    #expect(renamed.replacement
      == "@A @B\(ending)class AnotherVeryLongDeclaration {}")
  }

  @Test(
    "Width condition counts suffix and stops at physical line ending",
    arguments: ["\n", "\r\n", "\r"], [20, 21]
  )
  func suffixLineEnding(ending: String, maximumWidth: Int) throws {
    let original = "let r = send(1, 2).id\(ending)let followingDeclaration = 100"
    let file = try FileCollector.collect(source: original, path: "/App.swift")
    let call = try #require(file.calls.first)
    let layout = try call.arguments.replacement(
      whenLineExceeds: maximumWidth
    ) {
      for argument in call.arguments {
        Newline()
        argument
      }
      Newline()
    }

    let corrected = try file.source.replacement(applying: [layout])
    let expected = if maximumWidth == 20 {
      "let r = send(\(ending)  1,\(ending)  2\(ending)).id\(ending)let followingDeclaration = 100"
    } else {
      "let r = send(1, 2).id\(ending)let followingDeclaration = 100"
    }

    #expect(corrected.replacement.utf8.elementsEqual(expected.utf8))
  }

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
