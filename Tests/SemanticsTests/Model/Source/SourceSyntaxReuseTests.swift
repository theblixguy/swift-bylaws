import BylawsSemantics
import Foundation
import Testing

@Suite("Source syntax retention")
struct SourceSyntaxReuseTests {
  @Test(
    "Call query routes produce identical corrections and transport",
    arguments: [false, true]
  )
  func callQueries(syntaxQuery: Bool) throws {
    let file = try FileCollector.collect(
      source: "let result = send(first: 1, second: 2)", path: "/App.swift"
    )
    let calls = if syntaxQuery {
      file.syntaxNodes(of: .functionCall).compactMap(\.call)
    } else {
      file.calls
    }
    try #require(calls.count == 1)
    let call = try #require(calls.first)
    let snapshot = try call.source.snapshot
    let edit = try call.arguments.replacement {
      for argument in call.arguments {
        Newline()
        argument
      }
      Newline()
    }

    let corrected = try file.source.replacement(applying: [edit])
    let encoded = try JSONEncoder().encode(snapshot)
    let payload = try #require(JSONSerialization.jsonObject(with: encoded)
      as? [String: Any])
    let decoded = try JSONDecoder().decode(SourceSnapshot.self, from: encoded)

    #expect(corrected
      .replacement == "let result = send(\n  first: 1,\n  second: 2\n)")
    #expect(Set(payload.keys) == ["filePath", "text", "swiftLanguageMode"])
    #expect(payload["filePath"] as? String == "/App.swift")
    #expect(payload["text"] as? String ==
      "let result = send(first: 1, second: 2)")
    #expect(payload["swiftLanguageMode"] as? String == "6")
    #expect(decoded == snapshot)
    #expect(Set([snapshot]).contains(decoded))
  }

  @Test("Retained syntax preserves layout preview validation")
  func forgedPreview() throws {
    let file = try FileCollector.collect(
      source: "let result = send(first: 1, second: 2)", path: "/App.swift"
    )
    let call = try #require(file.syntaxNodes(of: .functionCall).first?.call)
    let edit = try call.arguments.replacement { call.arguments.reversed() }
    let forged = SourceFix.Edit(
      source: edit.source, replacement: "first: 1", layout: edit.layout
    )

    #expect(throws: SourceLayoutComposition.Failure.self) {
      try JSONEncoder().encode(forged)
    }
  }
}
