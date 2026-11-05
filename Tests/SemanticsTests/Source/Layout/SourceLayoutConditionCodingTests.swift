import BylawsSemantics
import Foundation
import Testing

@Suite("Layout condition transport")
struct SourceLayoutConditionCodingTests {
  @Test("Decoded conditions retain bounds and Boolean operations")
  func composedCondition() throws {
    let condition: SourceLayoutCondition =
      (.maximumLineLength(10..<16) && !.maximumLineLength(...14))
        || .maximumLineLength(Int.max...)
    let decoded = try JSONDecoder().decode(
      SourceLayoutCondition.self, from: JSONEncoder().encode(condition)
    )
    let file = try collect("let x = f(1, 2)")
    let arguments = try #require(file.calls.first).arguments
    let edit = try arguments.replacement(when: decoded) {
      Newline()
      Lines { arguments }
      Newline()
    }

    #expect(try file.source.replacement(applying: [edit])
      .replacement == "let x = f(\n  1,\n  2\n)")
  }

  @Test("Captured edits retain conditions after their parent moves them")
  func deferredCondition() throws {
    let file = try collect("let x = outer(first: inner(1, 2), second: 3)")
    let outer = try #require(file.calls.first { $0.name == "outer" })
    let inner = try #require(file.calls.first { $0.name == "inner" })
    let edits = [
      try outer.arguments.replacement {
        Newline()
        Lines { outer.arguments }
        Newline()
      },
      try inner.arguments.replacement(when: .maximumLineLength(...25)) {
        Newline()
        Lines { inner.arguments }
        Newline()
      },
    ]
    let decoded = try JSONDecoder().decode(
      [SourceFix.Edit].self, from: JSONEncoder().encode(edits)
    )

    #expect(try file.source.replacement(applying: decoded).replacement == """
    let x = outer(
      first: inner(
        1,
        2
      ),
      second: 3
    )
    """)
  }

  @Test("Decoded condition must agree with the correction preview")
  func changedCondition() throws {
    let file = try collect("let x = f(1, 2)")
    let arguments = try #require(file.calls.first).arguments
    let edit = try arguments.replacement(when: .maximumLineLength(15...)) {
      Newline()
      Lines { arguments }
      Newline()
    }
    var payload = try #require(JSONSerialization.jsonObject(
      with: JSONEncoder().encode(edit)
    ) as? [String: Any])
    var plan = try #require(payload["layout"] as? [String: Any])
    var mode = try #require(plan["mode"] as? [String: Any])
    var layout = try #require(mode["layout"] as? [String: Any])
    var formatting = try #require(layout["_0"] as? [String: Any])
    formatting["condition"] = try JSONSerialization.jsonObject(
      with: JSONEncoder().encode(SourceLayoutCondition.maximumLineLength(16...))
    )
    layout["_0"] = formatting
    mode["layout"] = layout
    plan["mode"] = mode
    payload["layout"] = plan
    let data = try JSONSerialization.data(withJSONObject: payload)

    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(SourceFix.Edit.self, from: data)
    }
  }

  private func collect(_ source: String) throws -> SourceFile {
    try FileCollector.collect(source: source, path: "/virtual/Condition.swift")
  }
}
