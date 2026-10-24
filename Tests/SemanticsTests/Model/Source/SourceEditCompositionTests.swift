import BylawsSemantics
import Testing

@Suite("Source edit composition")
struct SourceEditCompositionTests {
  @Test("Composition preserves surrounding Unicode and applies original ranges")
  func originalRanges() throws {
    let file = try FileCollector.collect(
      source: "let café = send(first: 1, second: 2)",
      path: "/App.swift"
    )
    let call = try #require(file.calls.first)
    let first = try #require(call.arguments.first)
    let second = try #require(call.arguments.last)
    let edits = [
      try second.expressionSource.replacement(with: "200"),
      try first.expressionSource.replacement(with: "100"),
    ]

    let edit = try call.source.replacement(applying: edits)

    #expect(edit.replacement == "send(first: 100, second: 200)")
    #expect(edit.source.text == "send(first: 1, second: 2)")
  }

  @Test("Raw multiline replacement preserves authored indentation bytes")
  func rawIndentation() throws {
    let source = try FileCollector.collect(
      source: "  foo()\n", path: "/App.swift"
    ).source
    let replacement = try source.slice(2..<7)
      .replacement(with: "foo()\n  bar()")

    let result = try source.replacement(applying: [replacement])

    #expect(result.replacement.utf8.elementsEqual("  foo()\n  bar()\n".utf8))
  }

  @Test("Standalone raw replacement keeps unindented continuation bytes")
  func rawContinuation() throws {
    let source = try FileCollector.collect(
      source: "  foo()\n", path: "/App.swift"
    ).source
    let replacement = try source.slice(2..<7)
      .replacement(with: "call(\n2\n)")

    let result = try source.replacement(applying: [replacement])

    #expect(result.replacement.utf8.elementsEqual("  call(\n2\n)\n".utf8))
  }

  @Test(
    "Adjacent indentation edit preserves raw continuation bytes",
    arguments: [
      ("    ", "foo()\n  bar()", "    foo()\n  bar()\n"),
      ("", "foo()\n  bar()", "foo()\n  bar()\n"),
      ("    ", "call(\n2\n)", "    call(\n2\n)\n"),
      ("", "call(\n2\n)", "call(\n2\n)\n"),
    ]
  )
  func adjacentIndentation(
    indentation: String, replacement: String, expected: String
  ) throws {
    let source = try FileCollector.collect(
      source: "  foo()\n", path: "/App.swift"
    ).source
    let prefix = try source.slice(0..<2).replacement(with: indentation)
    let content = try source.slice(2..<7).replacement(with: replacement)

    let result = try source.replacement(applying: [prefix, content])

    #expect(result.replacement.utf8.elementsEqual(expected.utf8))
  }

  @Test("Composition rejects foreign snapshots")
  func snapshots() throws {
    let file = try FileCollector.collect(
      source: "let value = 1",
      path: "/App.swift"
    )
    let other = try FileCollector.collect(
      source: "let value = 2",
      path: "/App.swift"
    )
    let source = try file.source

    #expect(throws: SourceError.differentSnapshots) {
      try source.replacement(applying: [other.source.replacement(with: "")])
    }
  }

  @Test("Composition rejects edits outside the containing slice")
  func bounds() throws {
    let file = try FileCollector.collect(
      source: "let value = send(1)",
      path: "/App.swift"
    )
    let call = try #require(file.calls.first)

    #expect(throws: SourceError.rangeOutOfBounds) {
      try call.source.replacement(applying: [file.source.replacement(with: "")])
    }
  }

  @Test("Composition rejects overlapping edits and repeated insertions")
  func conflicts() throws {
    let source = try FileCollector.collect(
      source: "let value = 1",
      path: "/App.swift"
    ).source
    let part = try source.slice(0..<3)
    let position = try source.slice(0..<0)

    #expect(throws: SourceError.overlappingEdits) {
      try source.replacement(applying: [
        part.replacement(with: "var"),
        part.replacement(with: "let"),
      ])
    }
    #expect(throws: SourceError.overlappingEdits) {
      try source.replacement(applying: [
        position.replacement(with: " "),
        position.replacement(with: "\n"),
      ])
    }
  }

  @Test(
    "Explicit composition rejects identical repeated edits",
    arguments: [false, true]
  )
  func repeatedEdits(insertion: Bool) throws {
    let source = try FileCollector.collect(
      source: "let value = 1", path: "/App.swift"
    ).source
    let edit = if insertion {
      try source.slice(0..<0).replacement(with: "// Keep\n")
    } else {
      try source.slice(0..<3).replacement(with: "var")
    }

    #expect(throws: SourceError.overlappingEdits) {
      try source.replacement(applying: [edit, edit])
    }
  }

  @Test("Composition permits adjacent edits and empty input")
  func boundaries() throws {
    let source = try FileCollector.collect(
      source: "let value = 1",
      path: "/App.swift"
    ).source
    let first = try source.slice(0..<3)
    let second = try source.slice(3..<4)

    let edit = try source.replacement(applying: [
      first.replacement(with: "var"),
      second.replacement(with: "  "),
    ])

    #expect(edit.replacement == "var  value = 1")
    #expect(try source.replacement(applying: []).replacement == source.text)
    let end = try source.slice(3..<3)
    #expect(try source.replacement(applying: [
      first.replacement(with: "var"),
      end.replacement(with: " "),
    ]).replacement == "var  value = 1")
  }
}
