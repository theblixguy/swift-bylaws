import BylawsSemantics
import Foundation
import Testing

@Suite("Contained list layouts")
struct ApplyingListLayoutTests {
  @Test("Each captured list receives its own arrangement")
  func multipleLists() throws {
    let file =
      try collect("send(values: [1, 2], lookup: [key: 3, other: 4], empty: [])")
    let call = try #require(file.syntaxNodes(of: .functionCall).first?.call)
    let arguments = call.arguments
    let collections = arguments.compactMap { $0.expression?.elements }
    var counts: [Int] = []
    let operation = try Layout(
      arguments,
      layout: Lines(arguments, boundaries: .newline)
    )
    .applying(toEach: collections) { elements in
      counts.append(elements.count)
      return .layout(Lines(elements, boundaries: .newline))
    }

    #expect(counts == [2, 2, 0])
    #expect(try applying(operation) == """
    send(
      values: [
        1,
        2
      ],
      lookup: [
        key: 3,
        other: 4
      ],
      empty: []
    )
    """)
  }

  @Test("Named functions can return stored layout descriptions")
  func storedDescription() throws {
    func arrangement(_ elements: [SourceNode]) -> LayoutContent<SourceNode> {
      .layout(Lines(elements, boundaries: .newline))
    }
    let file = try collect("send(values: [1, 2])")
    let call = try #require(file.syntaxNodes(of: .functionCall).first?.call)
    let arguments = call.arguments
    let collections = arguments.compactMap { $0.expression?.elements }
    let operation = try Layout(arguments, layout: Joined(arguments))
      .applying(toEach: collections, arrangement)

    #expect(try applying(operation) == """
    send(values: [
      1,
      2
    ])
    """)
  }

  @Test("Empty collection sequence retains parent layout")
  func noLists() throws {
    let file = try collect("send(first, second)")
    let call = try #require(file.syntaxNodes(of: .functionCall).first?.call)
    let arguments = call.arguments
    let empty: [[SourceNode]] = []
    var calls = 0
    let operation = try Layout(
      arguments,
      layout: Lines(arguments, boundaries: .newline)
    )
    .applying(toEach: empty) { elements in
      calls += 1
      return .layout(Lines(elements))
    }

    #expect(calls == 0)
    #expect(try applying(operation) == "send(\n  first,\n  second\n)")
  }

  @Test("Inactive parent retains contained layout candidates through encoding")
  func inactiveParent() throws {
    let file = try collect("send(values: [1, 2])")
    let call = try #require(file.syntaxNodes(of: .functionCall).first?.call)
    let arguments = call.arguments
    let collections = arguments.compactMap { $0.expression?.elements }
    var calls = 0
    let operation = try Layout(
      arguments, layout: Lines(arguments, boundaries: .newline),
      when: .maximumLineLength(100...)
    ).applying(toEach: collections) { elements in
      calls += 1
      return .layout(Lines(elements, boundaries: .newline))
    }
    let fix = try #require(operation.correction.fix)
    let restored = try JSONDecoder().decode(
      SourceFix.self, from: JSONEncoder().encode(fix)
    )

    #expect(calls == 1)
    #expect(operation.correction.outcome == .satisfied)
    #expect(fix.edits.isEmpty)
    #expect(fix.layoutCandidates.count == 1)
    #expect(try file.source.replacement(
      applying: restored.edits, layoutCandidates: restored.layoutCandidates
    ).replacement == "send(values: [1, 2])")
  }

  @Test("Containing movement rechecks conditions for each list")
  func finalPosition() throws {
    let file = try collect("outer(first: inner(values: [1, 2]), second: 3)")
    let outer = try #require(file.syntaxNodes(of: .functionCall)
      .compactMap(\.call).first { $0.name == "outer" })
    let inner = try #require(file.syntaxNodes(of: .functionCall)
      .compactMap(\.call).first { $0.name == "inner" })
    let parent = try Layout(
      outer.arguments,
      layout: Lines(outer.arguments, boundaries: .newline)
    )
    let child = try Layout(
      inner.arguments, layout: Joined(inner.arguments),
      when: .maximumLineLength(...35)
    ).applying(toEach: inner.arguments.compactMap { $0.expression?.elements }) {
      Lines($0, boundaries: .newline)
    }
    let fix = try #require(SourceCorrection(combining: [
      parent.correction,
      child.correction,
    ]).fix)

    #expect(try file.source.replacement(
      applying: fix.edits, layoutCandidates: fix.layoutCandidates
    ).replacement == """
    outer(
      first: inner(values: [
        1,
        2
      ]),
      second: 3
    )
    """)
  }

  @Test("Contained lists must share the parent snapshot")
  func foreignSnapshot() throws {
    let file = try collect("send(values: [1, 2])")
    let foreign = try FileCollector.collect(
      source: "send(values: [3, 4])", path: "/virtual/Other.swift"
    )
    let call = try #require(file.syntaxNodes(of: .functionCall).first?.call)
    let arguments = call.arguments
    let otherCall = try #require(foreign.syntaxNodes(of: .functionCall).first?
      .call)
    let collections = otherCall.arguments.compactMap { $0.expression?.elements }
    let parent = try Layout(arguments, layout: Joined(arguments))

    #expect(throws: SourceError.differentSnapshots) {
      try parent
        .applying(toEach: collections) { Lines($0, boundaries: .newline) }
    }
  }

  @Test("Contained lists must remain inside a retained parent element")
  func outsideParent() throws {
    let file = try collect("send(values: [1, 2])\nother(values: [3, 4])")
    let arguments = try #require(file.syntaxNodes(of: .functionCall)
      .compactMap(\.call).first { $0.name == "send" })
      .arguments
    let other = try #require(file.syntaxNodes(of: .functionCall)
      .compactMap(\.call).first { $0.name == "other" })
    let collections = other.arguments.compactMap { $0.expression?.elements }
    let parent = try Layout(arguments, layout: Joined(arguments))

    #expect(throws: SourceError.overlappingEdits) {
      try parent
        .applying(toEach: collections) { Lines($0, boundaries: .newline) }
    }
  }

  @Test("Unavailable contained layouts remain visible below parent threshold")
  func unavailableChild() throws {
    let file = try collect("send(values: [1, 2])")
    let call = try #require(file.syntaxNodes(of: .functionCall).first?.call)
    let arguments = call.arguments
    let collections = arguments.compactMap { $0.expression?.elements }
    let operation = try Layout(
      arguments, layout: Joined(arguments), when: .maximumLineLength(100...)
    ).applying(toEach: collections) { _ in
      SourceCorrection.unavailable("Keep the attached comment.")
    }

    #expect(operation.correction.outcome == .violation)
    #expect(operation.correction.reason == "Keep the attached comment.")
  }

  @Test(
    "Empty parent ignores unavailable child corrections after callback evaluation"
  )
  func emptyParent() throws {
    let file = try collect("send(values: [1, 2])")
    let call = try #require(file.syntaxNodes(of: .functionCall).first?.call)
    let collections = call.arguments.compactMap { $0.expression?.elements }
    let empty: [FunctionCall.Argument] = []
    var calls = 0
    let operation = try Layout(empty, layout: Joined(empty))
      .applying(toEach: collections) { _ in
        calls += 1
        return .layout(SourceLayout(SourceCorrection
            .unavailable("Keep the attached comment.")))
      }

    #expect(calls == 1)
    #expect(operation.correction.outcome == .notApplicable)
    #expect(operation.correction.fix == nil)
  }

  @Test(
    "Callback errors propagate from empty and inactive parents",
    arguments: [false, true]
  )
  func callbackFailure(empty: Bool) throws {
    enum Failure: Error { case stopped }
    func arrangement(_: [SourceNode]) throws -> LayoutContent<SourceNode> {
      throw Failure.stopped
    }
    let file = try collect("send(values: [1, 2])")
    let call = try #require(file.syntaxNodes(of: .functionCall).first?.call)
    let arguments = call.arguments
    let collections = arguments.compactMap { $0.expression?.elements }
    let retained = empty ? [] : arguments
    let parent = try Layout(
      retained, layout: Joined(retained), when: .maximumLineLength(100...)
    )

    #expect(throws: Failure.stopped) {
      try parent.applying(toEach: collections, arrangement)
    }
  }

  private func collect(_ source: String) throws -> SourceFile {
    try FileCollector.collect(source: source, path: "/virtual/Calls.swift")
  }

  private func applying(_ operation: some SourceCorrectionProviding) throws
    -> String
  {
    let fix = try #require(operation.correction.fix)
    let source = try #require(fix.edits.first).source.file
    return try source.replacement(applying: fix.edits).replacement
  }
}
