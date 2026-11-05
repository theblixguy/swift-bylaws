import Bylaws
import BylawsCore
import Testing

@Suite("Attached layout conditions")
struct AttachedLayoutConditionTests {
  @Test(
    "Containing layout rechecks attachment condition at final position",
    arguments: [false, true]
  )
  func movedLayout(matchesShortLines: Bool) async throws {
    let app = Codebase(root: .sources([
      "Sources/Calls.swift": "let result = outer(first: inner(values: [1, 2], option: true), second: 3)",
    ]))
    let outer = try #require(await app.calls.named("outer").first)
    let inner = try #require(await app.calls.named("inner").first)
    let elements = try #require(inner.arguments.first?.expression?.elements)
    let condition = SourceLayoutCondition.maximumLineLength(...60)
    let parent = try Layout(
      outer.arguments,
      layout: Lines(outer.arguments, boundaries: .newline)
    )
    let child = try Layout(
      inner.arguments, layout: Lines(inner.arguments, boundaries: .newline),
      when: matchesShortLines ? condition : !condition
    ).applying {
      try Layout(elements, layout: Lines(elements, boundaries: .newline))
    }
    let correction = SourceCorrection(combining: [
      parent.correction,
      child.correction,
    ])
    let fix = try #require(correction.fix)
    let source = try outer.source.file
    let replacement = try source.replacement(
      applying: fix.edits,
      layoutCandidates: fix.layoutCandidates
    )

    let expected = if matchesShortLines {
      """
      let result = outer(
        first: inner(
          values: [
            1,
            2
          ],
          option: true
        ),
        second: 3
      )
      """
    } else {
      """
      let result = outer(
        first: inner(values: [1, 2], option: true),
        second: 3
      )
      """
    }
    #expect(replacement.replacement == expected)
  }

  @Test("Satisfied parent applies attachments while its condition matches")
  func activeParent() async throws {
    let app = Codebase(root: .sources([
      "Sources/Calls.swift": """
      let result = send(
        values: [1, 2],
        option: true
      )
      """,
    ]))
    let call = try #require(await app.calls.first)
    let elements = try #require(call.arguments.first?.expression?.arrayElements)
    let layout = try Layout(
      call.arguments, layout: Lines(call.arguments, boundaries: .newline),
      when: .maximumLineLength(1...)
    )
    let operation = try layout.applying(Replace(elements[0], with: "3"))
    let fix = try #require(operation.correction.fix)
    let replacement = try call.source.file.replacement(applying: fix.edits)

    #expect(layout.correction.outcome == .satisfied)
    #expect(replacement.replacement == """
    let result = send(
      values: [3, 2],
      option: true
    )
    """)
  }
}
