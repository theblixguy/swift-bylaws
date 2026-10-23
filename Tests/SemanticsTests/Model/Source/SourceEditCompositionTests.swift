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
